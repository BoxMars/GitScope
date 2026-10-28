import Foundation

/// High level git commands for a single repository.
enum GitRepo {
    // MARK: - Open

    static func info(at path: String) async throws -> RepoInfo {
        let result = try await GitCLI.run(["rev-parse", "--show-toplevel", "--git-dir", "--git-common-dir", "--is-bare-repository", "--show-superproject-working-tree"], in: path)
        guard result.ok else { throw GitError.notARepository(path) }
        let lines = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 4 else { throw GitError.notARepository(path) }
        let root = lines[0]
        let gitDir = lines[1]
        let commonDir = lines[2]
        let bare = lines[3] == "true"
        let superproject = lines.count > 4 ? lines[4] : ""
        let absGitDir = gitDir.hasPrefix("/") ? gitDir : (root as NSString).appendingPathComponent(gitDir)
        let absCommonDir = commonDir.hasPrefix("/") ? commonDir : (root as NSString).appendingPathComponent(commonDir)
        return RepoInfo(root: root,
                        gitDir: absGitDir,
                        commonDir: absCommonDir,
                        isBare: bare,
                        isWorktree: absCommonDir != absGitDir,
                        isSubmodule: !superproject.isEmpty,
                        superproject: superproject.isEmpty ? nil : superproject)
    }

    static func remoteNames(at root: String) async throws -> [String] {
        let out = try await GitCLI.runChecked(["remote"], in: root)
        return out.split(separator: "\n").map(String.init)
    }

    // MARK: - Log

    private static let recordSeparator = "\u{1e}"
    private static let fieldSeparator = "\u{1f}"

    static func log(at root: String, limit: Int = 3000, ref: String? = nil) async throws -> [Commit] {
        let pretty = "--pretty=format:%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%cn%x1f%ce%x1f%ct%x1f%D%x1f%s%x1f%b%x1e"
        let refs: [String] = ref.map { [$0] } ?? ["--branches", "--tags", "--remotes"]
        var args = ["-c", "core.quotepath=false", "log", "--date-order", "--max-count=\(limit)", pretty] + refs
        var result = try await GitCLI.run(args, in: root)
        if !result.ok && ref == nil {
            args = ["-c", "core.quotepath=false", "log", "--date-order", "--max-count=\(limit)", pretty, "HEAD"]
            result = try await GitCLI.run(args, in: root)
        }
        if !result.ok {
            if result.errorText.contains("does not have any commits yet")
                || result.errorText.contains("unknown revision")
                || result.errorText.contains("bad default revision") {
                return []
            }
            throw GitError.commandFailed(result.errorText)
        }
        let out = result.stdout
        var commits: [Commit] = []
        for record in out.components(separatedBy: recordSeparator) {
            let trimmed = record.trimmingCharacters(in: .newlines)
            guard !trimmed.isEmpty else { continue }
            let f = trimmed.components(separatedBy: fieldSeparator)
            guard f.count >= 10 else { continue }
            let parents = f[1].split(separator: " ").map(String.init)
            let authorDate = Date(timeIntervalSince1970: Double(f[4]) ?? 0)
            let commitDate = Date(timeIntervalSince1970: Double(f[7]) ?? 0)
            let body = f.count > 10 ? f[10].trimmingCharacters(in: .newlines) : ""
            commits.append(Commit(hash: f[0],
                                  parents: parents,
                                  author: f[2],
                                  authorEmail: f[3],
                                  authorDate: authorDate,
                                  committer: f[5],
                                  committerDate: commitDate,
                                  subject: f[9],
                                  body: body,
                                  refs: parseRefs(f[8])))
        }
        return commits
    }

    static func countCommits(at root: String, ref: String?) async -> Int {
        let refs: [String] = ref.map { [$0] } ?? ["--branches", "--tags", "--remotes"]
        let result = try? await GitCLI.run(["rev-list", "--count"] + refs, in: root)
        guard let result, result.ok else { return 0 }
        return Int(result.trimmed) ?? 0
    }

    static func log(at root: String, limit: Int, path: String) async throws -> [Commit] {
        let pretty = "--pretty=format:%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%cn%x1f%ce%x1f%ct%x1f%D%x1f%s%x1f%b%x1e"
        let args = ["-c", "core.quotepath=false", "log", "--date-order", "--max-count=\(limit)", pretty, "--", path]
        let out = try await GitCLI.runChecked(args, in: root)
        var commits: [Commit] = []
        for record in out.components(separatedBy: recordSeparator) {
            let trimmed = record.trimmingCharacters(in: .newlines)
            guard !trimmed.isEmpty else { continue }
            let f = trimmed.components(separatedBy: fieldSeparator)
            guard f.count >= 10 else { continue }
            commits.append(Commit(hash: f[0],
                                  parents: f[1].split(separator: " ").map(String.init),
                                  author: f[2], authorEmail: f[3],
                                  authorDate: Date(timeIntervalSince1970: Double(f[4]) ?? 0),
                                  committer: f[5],
                                  committerDate: Date(timeIntervalSince1970: Double(f[7]) ?? 0),
                                  subject: f[9],
                                  body: f.count > 10 ? f[10].trimmingCharacters(in: .newlines) : "",
                                  refs: parseRefs(f[8])))
        }
        return commits
    }

    static func treeFiles(at revision: String, root: String) async throws -> [String] {
        let out = try await GitCLI.runChecked(["-c", "core.quotepath=false", "ls-tree", "-r", "--name-only", "-z", revision], in: root)
        return out.components(separatedBy: "\0").filter { !$0.isEmpty }
    }

    static func fileText(at path: String, revision: String, root: String) async throws -> (text: String, binary: Bool)? {
        guard let data = try await fileData(at: path, revision: revision, root: root) else { return nil }
        if data.contains(0) { return ("", true) }
        guard let text = String(data: data, encoding: .utf8) else { return ("", true) }
        return (text, false)
    }

    static func fileData(at path: String, revision: String, root: String) async throws -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: GitCLI.executable)
        process.currentDirectoryURL = URL(fileURLWithPath: root)
        process.arguments = ["show", "\(revision):\(path)"]
        var env = GitCLI.baseEnvironment
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    static func parseRefs(_ raw: String) -> [RefLabel] {
        guard !raw.isEmpty else { return [] }
        var refs: [RefLabel] = []
        for piece in raw.components(separatedBy: ", ") {
            var name = piece.trimmingCharacters(in: .whitespaces)
            var isHead = false
            if name.contains(" -> ") {
                isHead = true
                name = String(name.components(separatedBy: " -> ").last ?? "")
            }
            if name == "HEAD" {
                refs.append(RefLabel(name: "HEAD", kind: .head, isCurrent: true))
                continue
            }
            if name.hasPrefix("tag: ") {
                refs.append(RefLabel(name: String(name.dropFirst(5)), kind: .tag))
                continue
            }
            refs.append(RefLabel(name: name, kind: isHead ? .localBranch : .localBranch, isCurrent: isHead))
        }
        return refs
    }

    enum Operation: String {
        case merge, rebase, cherryPick, revert, bisect
        var title: String {
            switch self {
            case .merge: return "Merge in progress"
            case .rebase: return "Rebase in progress"
            case .cherryPick: return "Cherry-pick in progress"
            case .revert: return "Revert in progress"
            case .bisect: return "Bisect in progress"
            }
        }
    }

    static func operationState(at root: String) async -> Operation? {
        guard let info = try? await info(at: root) else { return nil }
        let fm = FileManager.default
        let gitDir = info.gitDir
        if fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("rebase-merge"))
            || fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("rebase-apply")) {
            return .rebase
        }
        if fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("MERGE_HEAD")) { return .merge }
        if fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("CHERRY_PICK_HEAD")) { return .cherryPick }
        if fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("REVERT_HEAD")) { return .revert }
        if fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("BISECT_LOG")) { return .bisect }
        return nil
    }

    // MARK: - Status

    static func status(at root: String) async throws -> WorkingStatus {
        let out = try await GitCLI.runChecked(
            ["-c", "core.quotepath=false", "status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"],
            in: root)
        var status = WorkingStatus()
        let parts = out.components(separatedBy: "\0")
        var i = 0
        while i < parts.count {
            let line = parts[i]
            i += 1
            if line.isEmpty { continue }
            if line.hasPrefix("# branch.head ") {
                let v = String(line.dropFirst("# branch.head ".count))
                if v == "(detached)" { status.detached = true } else { status.branch = v }
            } else if line.hasPrefix("# branch.upstream ") {
                status.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                for p in parts {
                    if p.hasPrefix("+"), let n = Int(p.dropFirst()) { status.ahead = n }
                    if p.hasPrefix("-"), let n = Int(p.dropFirst()) { status.behind = n }
                }
            } else if line.hasPrefix("1 ") {
                let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard fields.count >= 9 else { continue }
                let xy = String(fields[1])
                let path = String(fields[8])
                appendChange(xy: xy, path: path, oldPath: nil, into: &status)
            } else if line.hasPrefix("2 ") {
                let fields = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard fields.count >= 10 else { continue }
                let xy = String(fields[1])
                let path = String(fields[9])
                let oldPath = i < parts.count ? parts[i] : nil
                i += 1
                appendChange(xy: xy, path: path, oldPath: oldPath, into: &status)
            } else if line.hasPrefix("u ") {
                let fields = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard fields.count >= 11 else { continue }
                let path = String(fields[10])
                status.changes.append(FileChange(path: path, oldPath: nil, kind: .unmerged))
            } else if line.hasPrefix("? ") {
                let path = String(line.dropFirst(2))
                status.changes.append(FileChange(path: path, oldPath: nil, kind: .untracked))
            }
        }
        return status
    }

    private static func appendChange(xy: String, path: String, oldPath: String?, into status: inout WorkingStatus) {
        let chars = Array(xy)
        guard chars.count == 2 else { return }
        let indexChar = chars[0]
        let workChar = chars[1]

        func kind(for c: Character) -> ChangeKind? {
            switch c {
            case "M": return .modified
            case "A": return .added
            case "D": return .deleted
            case "R": return .renamed
            case "C": return .copied
            case "T": return .typeChanged
            case "U": return .unmerged
            default: return nil
            }
        }

        if let k = kind(for: indexChar) {
            status.changes.append(FileChange(path: path, oldPath: oldPath, kind: k, staged: true))
        }
        if let k = kind(for: workChar) {
            status.changes.append(FileChange(path: path, oldPath: oldPath, kind: k, staged: false))
        }
    }

    // MARK: - Branches / tags / stashes / worktrees

    static func branches(at root: String) async throws -> [Branch] {
        let format = "%(refname)%00%(objectname)%00%(HEAD)%00%(upstream:short)%00%(upstream:track)%00%(committerdate:unix)%00%(contents:subject)"
        let out = try await GitCLI.runChecked(["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes"], in: root)
        var result: [Branch] = []
        for line in out.split(separator: "\n") {
            let f = line.components(separatedBy: "\0")
            guard f.count >= 5 else { continue }
            let fullName = f[0]
            let isRemote = fullName.hasPrefix("refs/remotes/")
            let name = fullName.replacingOccurrences(of: "refs/heads/", with: "")
                .replacingOccurrences(of: "refs/remotes/", with: "")
            if name.hasSuffix("/HEAD") { continue }
            var ahead = 0
            var behind = 0
            let track = f[4]
            if let m = track.range(of: "ahead ") {
                let rest = track[m.upperBound...]
                ahead = Int(rest.prefix(while: { $0.isNumber })) ?? 0
            }
            if let m = track.range(of: "behind ") {
                let rest = track[m.upperBound...]
                behind = Int(rest.prefix(while: { $0.isNumber })) ?? 0
            }
            result.append(Branch(name: name,
                                 fullName: fullName,
                                 hash: f[1],
                                 isRemote: isRemote,
                                 isCurrent: f[2] == "*",
                                 upstream: f[3].isEmpty ? nil : f[3],
                                 ahead: ahead,
                                 behind: behind,
                                 lastCommitDate: Date(timeIntervalSince1970: Double(f[5]) ?? 0)))
        }
        return result.sorted { a, b in
            if a.isRemote != b.isRemote { return !a.isRemote }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func tags(at root: String) async throws -> [Tag] {
        let out = try await GitCLI.runChecked(
            ["for-each-ref", "--format=%(refname:short)%00%(objectname)%00%(contents:subject)%00%(creatordate:unix)", "refs/tags"], in: root)
        return out.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\0")
            guard f.count >= 3 else { return nil }
            return Tag(name: f[0], hash: f[1], message: f[2],
                       date: Double(f.count > 3 ? f[3] : "") .map { Date(timeIntervalSince1970: $0) })
        }
    }

    static func stashes(at root: String) async throws -> [Stash] {
        let out = try await GitCLI.runChecked(["stash", "list", "--format=%gd%x00%H%x00%gs%x00%ct"], in: root)
        return out.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\0")
            guard f.count >= 3 else { return nil }
            let index = Int(f[0].replacingOccurrences(of: "stash@{", with: "").replacingOccurrences(of: "}", with: "")) ?? 0
            return Stash(index: index, hash: f[1], message: f[2],
                         date: Double(f.count > 3 ? f[3] : "").map { Date(timeIntervalSince1970: $0) })
        }
    }

    static func worktrees(at root: String) async throws -> [Worktree] {
        let out = try await GitCLI.runChecked(["worktree", "list", "--porcelain"], in: root)
        var result: [Worktree] = []
        var current: [String: String] = [:]
        func flush() {
            if let path = current["worktree"] {
                result.append(Worktree(path: path,
                                       head: current["HEAD"] ?? "",
                                       branch: current["branch"]?.replacingOccurrences(of: "refs/heads/", with: ""),
                                       isBare: current["bare"] != nil,
                                       isDetached: current["detached"] != nil,
                                       isLocked: current["locked"] != nil))
            }
            current = [:]
        }
        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { flush(); continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            current[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        flush()
        return result
    }

    // MARK: - Commit details

    static func files(inCommit hash: String, at root: String) async throws -> [FileChange] {
        let out = try await GitCLI.runChecked(
            ["-c", "core.quotepath=false", "show", "--format=", "--name-status", "-z", "-M", hash], in: root)
        let parts = out.components(separatedBy: "\0")
        var changes: [FileChange] = []
        var i = 0
        while i < parts.count {
            let token = parts[i]
            i += 1
            guard !token.isEmpty else { continue }
            let code = token.first.map(String.init) ?? ""
            guard let kind = ChangeKind(rawValue: code) else { continue }
            if kind == .renamed || kind == .copied {
                guard i + 1 < parts.count else { break }
                let old = parts[i]
                let new = parts[i + 1]
                i += 2
                changes.append(FileChange(path: new, oldPath: old, kind: kind))
            } else {
                guard i < parts.count else { break }
                let path = parts[i]
                i += 1
                changes.append(FileChange(path: path, oldPath: nil, kind: kind))
            }
        }
        return changes
    }

    static func diff(forCommit hash: String, path: String, at root: String, ignoreWhitespace: Bool = false) async throws -> FileDiff {
        let parentOut = try await GitCLI.runChecked(["rev-list", "--parents", "-n", "1", hash], in: root)
        let fields = parentOut.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" }).map(String.init)
        var args: [String]
        if fields.count > 1 {
            args = ["-c", "core.quotepath=false", "diff", "--no-color", "--no-ext-diff", "-M", "-U3"]
        } else {
            args = ["-c", "core.quotepath=false", "show", "--no-color", "--no-ext-diff", "-M", "-U3", "--format="]
        }
        if ignoreWhitespace { args.append("-w") }
        if !fields.isEmpty {
            if fields.count > 1 {
                args.append(contentsOf: [fields[1], hash, "--", path])
            } else {
                args.append(contentsOf: [hash, "--", path])
            }
        }
        let out = try await GitCLI.runChecked(args, in: root)
        var parsed = DiffParser.parse(out)
        if parsed.isEmpty {
            return FileDiff(path: path, oldPath: nil, hunks: [], isBinary: false, rawText: "")
        }
        parsed[0].path = path
        return parsed[0]
    }

    static func diffWorking(path: String, staged: Bool, at root: String, ignoreWhitespace: Bool = false) async throws -> FileDiff {
        var args = ["-c", "core.quotepath=false", "diff", "--no-color", "--no-ext-diff", "-M", "-U3"]
        if ignoreWhitespace { args.append("-w") }
        if staged { args.append("--cached") }
        args.append(contentsOf: ["--", path])
        let out = try await GitCLI.runChecked(args, in: root)
        var parsed = DiffParser.parse(out)
        if parsed.isEmpty {
            return FileDiff(path: path, oldPath: nil, hunks: [], isBinary: false, rawText: "")
        }
        parsed[0].path = path
        return parsed[0]
    }

    /// Diff of a file for an untracked file (diff against /dev/null).
    static func diffUntracked(path: String, at root: String) async throws -> FileDiff {
        let full = (root as NSString).appendingPathComponent(path)
        guard let data = FileManager.default.contents(atPath: full) else {
            return FileDiff(path: path, oldPath: nil, hunks: [], isBinary: false, rawText: "")
        }
        if data.contains(0) {
            return FileDiff(path: path, oldPath: nil, hunks: [], isBinary: true, rawText: "")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: "\n")
        var diffLines: [DiffLine] = []
        for (idx, line) in lines.enumerated() {
            diffLines.append(DiffLine(kind: .added, oldNumber: nil, newNumber: idx + 1, text: line))
        }
        let hunk = DiffHunk(header: "@@ -0,0 +1,\(diffLines.count) @@", oldStart: 0, oldCount: 0,
                            newStart: 1, newCount: diffLines.count, lines: diffLines)
        return FileDiff(path: path, oldPath: nil, hunks: [hunk], isBinary: false, rawText: "")
    }

    static func rawFile(at path: String, commit: String?, root: String) async throws -> String? {
        let args: [String]
        if let commit {
            args = ["show", "\(commit):\(path)"]
        } else {
            args = ["show", "HEAD:\(path)"]
        }
        let r = try await GitCLI.run(args, in: root)
        return r.ok ? r.stdout : nil
    }

    // MARK: - Blame

    struct BlameLine: Identifiable {
        var id: Int
        var hash: String
        var author: String
        var date: Date
        var lineNumber: Int
        var text: String
        var summary: String
    }

    static func blame(path: String, at root: String) async throws -> [BlameLine] {
        let out = try await GitCLI.runChecked(["blame", "--line-porcelain", "--", path], in: root)
        var lines: [BlameLine] = []
        var hash = ""
        var author = ""
        var date = Date()
        var summary = ""
        var lineNumber = 0
        for raw in out.components(separatedBy: "\n") {
            if raw.hasPrefix("\t") {
                lines.append(BlameLine(id: lineNumber, hash: hash, author: author, date: date,
                                       lineNumber: lineNumber, text: String(raw.dropFirst()), summary: summary))
                continue
            }
            let parts = raw.split(separator: " ", maxSplits: 3).map(String.init)
            if parts.count >= 3, parts[0].count == 40, Int(parts[2]) != nil {
                hash = parts[0]
                lineNumber = Int(parts[2]) ?? 0
            } else if raw.hasPrefix("author ") {
                author = String(raw.dropFirst("author ".count))
            } else if raw.hasPrefix("author-time ") {
                date = Date(timeIntervalSince1970: Double(raw.dropFirst("author-time ".count)) ?? 0)
            } else if raw.hasPrefix("summary ") {
                summary = String(raw.dropFirst("summary ".count))
            }
        }
        return lines
    }

    // MARK: - Reflog

    struct ReflogEntry: Identifiable, Hashable {
        var id: String { "\(hash)-\(index)" }
        var index: Int
        var hash: String
        var selector: String
        var message: String
        var date: Date
    }

    static func reflog(at root: String, limit: Int = 500) async throws -> [ReflogEntry] {
        let out = try await GitCLI.runChecked(
            ["reflog", "show", "--date=format:%Y-%m-%d %H:%M", "--format=%h%x00%gd%x00%gs%x00%gD", "-n", "\(limit)"], in: root)
        return out.split(separator: "\n").enumerated().compactMap { idx, line in
            let f = line.components(separatedBy: "\0")
            guard f.count >= 3 else { return nil }
            return ReflogEntry(index: idx, hash: f[0], selector: f[1], message: f[2],
                               date: Date(timeIntervalSince1970: 0))
        }
    }

    // MARK: - Submodules

    static func submodules(at root: String) async throws -> [(path: String, hash: String, status: String)] {
        let r = try await GitCLI.run(["submodule", "status"], in: root)
        guard r.ok, !r.stdout.isEmpty else { return [] }
        return r.stdout.split(separator: "\n").compactMap { line in
            let s = String(line)
            guard s.count > 42 else { return nil }
            let status = String(s.prefix(1))
            let hash = String(s.dropFirst(1).prefix(40))
            let rest = String(s.dropFirst(42))
            return (rest, hash, status)
        }
    }
}
