import Foundation
import SwiftUI

@MainActor
final class RepoSession: ObservableObject, Identifiable {
    let ref: RepositoryRef
    var id: String { ref.path }
    let root: String

    @Published var info: RepoInfo?
    @Published var commits: [Commit] = []
    @Published var graph = GraphLayout()
    @Published var branches: [Branch] = []
    @Published var tags: [Tag] = []
    @Published var stashes: [Stash] = []
    @Published var worktrees: [Worktree] = []
    @Published var remotes: [String] = []
    @Published var submodules: [Submodule] = []
    @Published var status = WorkingStatus()
    @Published var operation: GitRepo.Operation?

    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var isBusy = false
    @Published var busyMessage: String?
    @Published var errorMessage: String?

    // Layout mode: history list vs working directory changes.
    enum PaneMode: String {
        case history
        case changes
    }

    @Published var mode: PaneMode = .history

    // Selection
    @Published var selection: HistorySelection = .workingDirectory
    @Published var selectedCommit: Commit?
    @Published var commitFiles: [FileChange] = []
    @Published var selectedFile: FileChange?
    @Published var diff: FileDiff?
    @Published var isDiffLoading = false
    @Published var imagePair: ImagePair?
    @Published var inspector: Inspector?
    @Published var showRebaseSheet = false
    @Published var showWorktreeSheet = false
    @Published var ignoreWhitespace = false {
        didSet { Task { await reloadCurrentDiff() } }
    }
    @Published var detailTab: CommitDetailTab = .changes
    @Published var treeFiles: [String] = []
    @Published var treeSelection: String?
    @Published var treeContent: String?
    @Published var treeIsBinary = false

    enum CommitDetailTab: String, CaseIterable, Identifiable {
        case changes, tree
        var id: String { rawValue }
        var title: String { self == .changes ? "Changes" : "Files" }
    }

    // Filters
    @Published var filterRef: String?
    @Published var searchText = ""
    @Published var logLimit = 2000
    @Published var hasMore = false

    // Working copy selection
    @Published var selectedChange: FileChange?

    private var lastRefresh = Date.distantPast
    private var didRestoreSelection = false
    private var lastCommitHash: String?

    static let selectionKey = "gitscope.lastSelections"
    static let modeKey = "gitscope.paneModes"

    static func storedMode(for root: String) -> PaneMode? {
        guard let raw = (UserDefaults.standard.dictionary(forKey: modeKey) as? [String: String])?[root] else { return nil }
        return PaneMode(rawValue: raw)
    }

    static func storeMode(_ mode: PaneMode, for root: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: modeKey) as? [String: String]) ?? [:]
        dict[root] = mode.rawValue
        UserDefaults.standard.set(dict, forKey: modeKey)
    }

    static func storedSelection(for root: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: selectionKey) as? [String: String])?[root]
    }

    static func storeSelection(_ hash: String?, for root: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: selectionKey) as? [String: String]) ?? [:]
        if let hash {
            dict[root] = hash
        } else {
            dict.removeValue(forKey: root)
        }
        UserDefaults.standard.set(dict, forKey: selectionKey)
    }

    struct ImagePair {
        var path: String
        var old: Data?
        var new: Data?
    }

    enum Inspector: Identifiable {
        case blame(String)
        case fileHistory(String)
        case reflog
        case submodules
        case stash(Stash)
        case refList(String)

        var id: String {
            switch self {
            case .blame(let path): return "blame:\(path)"
            case .fileHistory(let path): return "history:\(path)"
            case .reflog: return "reflog"
            case .submodules: return "submodules"
            case .stash(let stash): return "stash:\(stash.index)"
            case .refList(let kind): return "refs:\(kind)"
            }
        }
    }

    enum HistorySelection: Hashable {
        case workingDirectory
        case commit(String)
    }

    init(ref: RepositoryRef) {
        self.ref = ref
        self.root = ref.path
    }

    // MARK: - Derived

    var displayCommits: [Commit] {
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return commits }
        return commits.filter {
            $0.subject.localizedCaseInsensitiveContains(term)
                || $0.body.localizedCaseInsensitiveContains(term)
                || $0.author.localizedCaseInsensitiveContains(term)
                || $0.authorEmail.localizedCaseInsensitiveContains(term)
                || $0.hash.hasPrefix(term)
                || $0.shortHash.hasPrefix(term)
        }
    }

    var currentBranch: Branch? {
        branches.first { $0.isCurrent }
    }

    var localBranches: [Branch] { branches.filter { !$0.isRemote } }
    var remoteBranches: [Branch] { branches.filter(\.isRemote) }

    var isDirty: Bool { !status.changes.isEmpty }

    var selectionTitle: String {
        switch selection {
        case .workingDirectory: return "Working Directory"
        case .commit(let hash): return commits.first(where: { $0.hash == hash })?.shortHash ?? String(hash.prefix(7))
        }
    }

    var selectedDiffFile: FileChange? {
        switch selection {
        case .workingDirectory: return selectedChange
        case .commit: return selectedFile
        }
    }

    // MARK: - Loading

    func refresh(force: Bool = false) async {
        if isLoading { return }
        if !force && Date().timeIntervalSince(lastRefresh) < 2 { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let infoTask = GitRepo.info(at: root)
            async let branchesTask = GitRepo.branches(at: root)
            async let tagsTask = GitRepo.tags(at: root)
            async let stashesTask = GitRepo.stashes(at: root)
            async let worktreesTask = GitRepo.worktrees(at: root)
            async let statusTask = GitRepo.status(at: root)
            async let submodulesTask = GitRepo.submodules(at: root)
            async let remotesTask = GitRepo.remoteNames(at: root)
            async let logTask = GitRepo.log(at: root, limit: logLimit + 1, ref: filterRef)

            let (info, branches, tags, stashes, worktrees, status, remotes, log, submodules) =
                try await (infoTask, branchesTask, tagsTask, stashesTask, worktreesTask, statusTask, remotesTask, logTask, submodulesTask)

            self.info = info
            self.branches = branches
            self.tags = tags
            self.stashes = stashes
            self.worktrees = worktrees
            self.status = status
            self.remotes = remotes
            self.submodules = submodules.map { Submodule(path: $0.path, hash: $0.hash, status: $0.status) }
            self.operation = await GitRepo.operationState(at: root)
            self.hasMore = log.count > logLimit
            var loaded = Array(log.prefix(logLimit))
            applyRefKinds(&loaded)
            self.commits = loaded
            self.graph = GraphLayout.compute(commits: loaded)
            self.lastRefresh = Date()
            self.hasLoaded = true
            resyncSelection()
            if !didRestoreSelection {
                didRestoreSelection = true
                if Self.storedMode(for: root) == .changes {
                    selectWorkingDirectory()
                } else if let stored = Self.storedSelection(for: root),
                          let commit = loaded.first(where: { $0.hash == stored }) {
                    Task { await self.select(commit: commit) }
                } else if let newest = loaded.first {
                    // First open: land on history with the latest commit selected.
                    Task { await self.select(commit: newest) }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Cheap metadata load for sidebar rows: branch name + dirty state only.
    func loadStatusOnly() async {
        guard !hasLoaded else { return }
        if let status = try? await GitRepo.status(at: root) {
            self.status = status
        }
        if let branches = try? await GitRepo.branches(at: root) {
            self.branches = branches
        }
    }

    private var lastAutoLoad = Date.distantPast

    func autoLoadMoreIfNeeded() {
        guard hasMore, !isLoading, Date().timeIntervalSince(lastAutoLoad) > 0.8 else { return }
        lastAutoLoad = Date()
        Task { await loadMore() }
    }

    func loadMore() async {
        logLimit += 2000
        await refresh(force: true)
    }

    private func applyRefKinds(_ commits: inout [Commit]) {
        let locals = Set(localBranches.map(\.name))
        let remotes = Set(remoteBranches.map(\.name))
        let tagNames = Set(tags.map(\.name))
        for i in commits.indices {
            for j in commits[i].refs.indices {
                let name = commits[i].refs[j].name
                if name == "HEAD" {
                    commits[i].refs[j].kind = .head
                } else if tagNames.contains(name) {
                    commits[i].refs[j].kind = .tag
                } else if remotes.contains(name) {
                    commits[i].refs[j].kind = .remoteBranch
                } else if locals.contains(name) {
                    commits[i].refs[j].kind = .localBranch
                }
            }
        }
    }

    private func resyncSelection() {
        switch selection {
        case .workingDirectory:
            selectedCommit = nil
            if let change = selectedChange {
                selectedChange = status.changes.first(where: { $0.id == change.id }) ?? status.changes.first
            } else {
                selectedChange = status.changes.first
            }
            if let change = selectedChange {
                Task { await loadWorkingDiff(for: change) }
            } else {
                diff = nil
            }
        case .commit(let hash):
            if let commit = commits.first(where: { $0.hash == hash }) {
                selectedCommit = commit
                Task { await loadCommit(commit, keepFile: true) }
            } else {
                selection = .workingDirectory
                selectedCommit = nil
            }
        }
    }

    // MARK: - Selection handling

    func setMode(_ newMode: PaneMode) {
        guard mode != newMode else { return }
        mode = newMode
        switch newMode {
        case .changes:
            selectWorkingDirectory()
        case .history:
            if case .commit = selection { return }
            if let hash = lastCommitHash, let commit = commits.first(where: { $0.hash == hash }) {
                Task { await select(commit: commit) }
            } else if let first = commits.first {
                Task { await select(commit: first) }
            }
        }
    }

    func selectWorkingDirectory() {
        Self.storeSelection(nil, for: root)
        Self.storeMode(.changes, for: root)
        mode = .changes
        selection = .workingDirectory
        selectedCommit = nil
        commitFiles = []
        diff = nil
        selectedChange = status.changes.first
        if let change = selectedChange {
            Task { await loadWorkingDiff(for: change) }
        }
    }

    func select(commit: Commit) async {
        Self.storeSelection(commit.hash, for: root)
        Self.storeMode(.history, for: root)
        lastCommitHash = commit.hash
        mode = .history
        selection = .commit(commit.hash)
        selectedCommit = commit
        selectedFile = nil
        diff = nil
        await loadCommit(commit, keepFile: false)
    }

    private func loadCommit(_ commit: Commit, keepFile: Bool) async {
        do {
            let files = try await GitRepo.files(inCommit: commit.hash, at: root)
            guard case .commit(let hash) = selection, hash == commit.hash else { return }
            commitFiles = files
            let file: FileChange?
            if keepFile, let existing = selectedFile, let match = files.first(where: { $0.path == existing.path }) {
                file = match
            } else {
                file = files.first
            }
            selectedFile = file
            if let file {
                await loadCommitDiff(file, commit: commit)
            } else {
                diff = nil
            }
            if detailTab == .tree {
                treeFiles = []
                treeSelection = nil
                await loadTree()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectCommitFile(_ file: FileChange) async {
        selectedFile = file
        guard case .commit(let hash) = selection, let commit = commits.first(where: { $0.hash == hash }) else { return }
        await loadCommitDiff(file, commit: commit)
    }

    private func loadCommitDiff(_ file: FileChange, commit: Commit) async {
        isDiffLoading = true
        defer { isDiffLoading = false }
        do {
            let result = try await GitRepo.diff(forCommit: commit.hash, path: file.path, at: root, ignoreWhitespace: ignoreWhitespace)
            if result.isBinary && ImageFile.isImage(file.path) {
                var oldData: Data?
                if let parent = commit.parents.first {
                    oldData = (try? await GitRepo.fileData(at: file.path, revision: parent, root: self.root)) ?? nil
                }
                let newData = (try? await GitRepo.fileData(at: file.path, revision: commit.hash, root: self.root)) ?? nil
                imagePair = ImagePair(path: file.path, old: oldData, new: newData)
            } else {
                imagePair = nil
            }
            guard case .commit(let hash) = selection, hash == commit.hash, selectedFile?.path == file.path else { return }
            diff = result
        } catch {
            diff = nil
            errorMessage = error.localizedDescription
        }
    }

    func selectChange(_ change: FileChange) async {
        selectedChange = change
        await loadWorkingDiff(for: change)
    }

    private func loadWorkingDiff(for change: FileChange) async {
        isDiffLoading = true
        defer { isDiffLoading = false }
        do {
            let result: FileDiff
            if change.kind == .unmerged {
                result = conflictDiff(path: change.path)
            } else if change.kind == .untracked {
                result = try await GitRepo.diffUntracked(path: change.path, at: root)
            } else {
                result = try await GitRepo.diffWorking(path: change.path, staged: change.staged, at: root)
            }
            guard selectedChange?.id == change.id else { return }
            diff = result
        } catch {
            diff = nil
            errorMessage = error.localizedDescription
        }
    }

    private func conflictDiff(path: String) -> FileDiff {
        let full = (root as NSString).appendingPathComponent(path)
        guard let text = try? String(contentsOfFile: full, encoding: .utf8) else {
            return FileDiff(path: path, oldPath: nil, hunks: [], isBinary: false, rawText: "")
        }
        var lines: [DiffLine] = []
        var section: DiffLineKind = .context
        var number = 0
        for raw in text.components(separatedBy: "\n") {
            number += 1
            if raw.hasPrefix("<<<<<<<") {
                section = .removed
            } else if raw.hasPrefix("=======") {
                section = .added
            } else if raw.hasPrefix(">>>>>>>") {
                section = .context
            }
            lines.append(DiffLine(kind: section, oldNumber: number, newNumber: number, text: raw))
        }
        let hunk = DiffHunk(header: "@@ conflict — resolve with Ours / Theirs / Mark resolved @@",
                            oldStart: 1, oldCount: lines.count, newStart: 1, newCount: lines.count, lines: lines)
        return FileDiff(path: path, oldPath: nil, hunks: [hunk], isBinary: false, rawText: text)
    }

    private func reloadCurrentDiff() async {
        switch selection {
        case .workingDirectory:
            if let change = selectedChange { await loadWorkingDiff(for: change) }
        case .commit:
            if let file = selectedFile, let commit = selectedCommit {
                await loadCommitDiff(file, commit: commit)
            }
        }
    }

    // MARK: - Tree

    func loadTree() async {
        guard case .commit(let hash) = selection else { return }
        if treeFiles.isEmpty || treeSelection == nil {
            treeFiles = (try? await GitRepo.treeFiles(at: hash, root: root)) ?? []
        }
        if treeSelection == nil { treeSelection = treeFiles.first }
        if let path = treeSelection { await loadTreeFile(path) }
    }

    func selectTreeFile(_ path: String) async {
        treeSelection = path
        await loadTreeFile(path)
    }

    private func loadTreeFile(_ path: String) async {
        guard case .commit(let hash) = selection else { return }
        let result = try? await GitRepo.fileText(at: path, revision: hash, root: root)
        treeContent = result?.text
        treeIsBinary = result?.binary ?? false
    }

    // MARK: - Filtering

    func setFilterRef(_ ref: String?) async {
        filterRef = ref
        await refresh(force: true)
    }

    // MARK: - Staging

    func stage(_ change: FileChange) async {
        await perform("Stage") {
            _ = try await GitCLI.runChecked(["add", "-A", "--", change.path], in: self.root)
        }
    }

    func unstage(_ change: FileChange) async {
        await perform("Unstage") {
            _ = try await GitCLI.run(["reset", "-q", "HEAD", "--", change.path], in: self.root)
        }
    }

    func stageAll() async {
        await perform("Stage all") {
            _ = try await GitCLI.runChecked(["add", "-A"], in: self.root)
        }
    }

    func unstageAll() async {
        await perform("Unstage all") {
            _ = try await GitCLI.run(["reset", "-q", "HEAD"], in: self.root)
        }
    }

    func discard(_ change: FileChange) async {
        await perform("Discard") {
            if change.kind == .untracked {
                let full = (self.root as NSString).appendingPathComponent(change.path)
                try? FileManager.default.removeItem(atPath: full)
            } else {
                _ = try await GitCLI.run(["checkout", "--", change.path], in: self.root)
            }
        }
    }

    func stageHunk(path: String, hunk: DiffHunk, staged: Bool) async {
        let patch = PatchBuilder.patch(path: path, hunk: hunk, staged: staged)
        await perform(staged ? "Unstage hunk" : "Stage hunk") {
            var args = ["apply", "--cached"]
            if staged { args.append("--reverse") }
            _ = try await GitCLI.runChecked(args, in: self.root, input: patch)
        }
    }

    // MARK: - Commit

    @discardableResult
    func commit(message: String, amend: Bool = false, stageAllFirst: Bool = false) async -> Bool {
        await perform(amend ? "Amend" : "Commit") {
            if stageAllFirst {
                _ = try await GitCLI.runChecked(["add", "-A"], in: self.root)
            }
            var args = ["commit", "-F", "-"]
            if amend { args.append("--amend") }
            _ = try await GitCLI.runChecked(args, in: self.root, input: message)
        }
    }

    // MARK: - Branch / tag operations

    func checkout(_ branch: Branch) async {
        if branch.isRemote {
            let short = branch.shortName
            await perform("Checkout \(short)") {
                _ = try await GitCLI.runChecked(["switch", short], in: self.root)
            }
        } else {
            await perform("Checkout \(branch.name)") {
                _ = try await GitCLI.runChecked(["switch", branch.name], in: self.root)
            }
        }
    }

    func checkoutCommit(_ hash: String) async {
        await perform("Checkout commit") {
            _ = try await GitCLI.runChecked(["switch", "--detach", hash], in: self.root)
        }
    }

    func createBranch(name: String, startPoint: String?) async {
        await perform("Create branch") {
            var args = ["switch", "-c", name]
            if let startPoint { args.append(startPoint) }
            _ = try await GitCLI.runChecked(args, in: self.root)
        }
    }

    func deleteBranch(_ branch: Branch, force: Bool) async {
        await perform("Delete branch") {
            _ = try await GitCLI.runChecked(["branch", force ? "-D" : "-d", branch.name], in: self.root)
        }
    }

    func renameBranch(_ branch: Branch, to newName: String) async {
        await perform("Rename branch") {
            _ = try await GitCLI.runChecked(["branch", "-m", branch.name, newName], in: self.root)
        }
    }

    func createTag(name: String, message: String?, at hash: String?) async {
        await perform("Create tag") {
            var args = ["tag"]
            if let message, !message.isEmpty {
                args.append(contentsOf: ["-a", name, "-m", message])
            } else {
                args.append(name)
            }
            if let hash { args.append(hash) }
            _ = try await GitCLI.runChecked(args, in: self.root)
        }
    }

    func deleteTag(_ tag: Tag) async {
        await perform("Delete tag") {
            _ = try await GitCLI.runChecked(["tag", "-d", tag.name], in: self.root)
        }
    }

    // MARK: - Remote operations

    func fetch() async {
        await perform("Fetch", refreshAfter: true) {
            _ = try await GitCLI.runChecked(["fetch", "--all", "--prune"], in: self.root)
        }
    }

    func pull() async {
        await perform("Pull", refreshAfter: true) {
            _ = try await GitCLI.runChecked(["pull", "--no-rebase"], in: self.root)
        }
    }

    func push(setUpstream: Bool = false) async {
        await perform("Push", refreshAfter: true) {
            if setUpstream, let branch = self.currentBranch?.name {
                _ = try await GitCLI.runChecked(["push", "--set-upstream", "origin", branch], in: self.root)
                return
            }
            let result = try await GitCLI.run(["push"], in: self.root)
            if result.ok { return }
            if result.errorText.contains("no upstream branch"),
               let branch = self.currentBranch?.name,
               !self.remotes.isEmpty {
                _ = try await GitCLI.runChecked(["push", "--set-upstream", self.remotes[0], branch], in: self.root)
                return
            }
            throw GitError.commandFailed(result.errorText)
        }
    }

    // MARK: - Stash

    func promptStash() {
        let alert = NSAlert()
        alert.messageText = "Stash changes"
        alert.informativeText = "Save the working directory changes to a new stash."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Message (optional)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Stash")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let message = field.stringValue.trimmingCharacters(in: .whitespaces)
            Task { await stashPush(message: message.isEmpty ? nil : message) }
        }
    }

    func stashPush(message: String?) async {
        await perform("Stash") {
            var args = ["stash", "push"]
            if let message, !message.isEmpty { args.append(contentsOf: ["-m", message]) }
            _ = try await GitCLI.runChecked(args, in: self.root)
        }
    }

    func stashPop(_ stash: Stash) async {
        await perform("Stash pop") {
            _ = try await GitCLI.runChecked(["stash", "pop", "stash@{\(stash.index)}"], in: self.root)
        }
    }

    func stashApply(_ stash: Stash) async {
        await perform("Stash apply") {
            _ = try await GitCLI.runChecked(["stash", "apply", "stash@{\(stash.index)}"], in: self.root)
        }
    }

    func stashDrop(_ stash: Stash) async {
        await perform("Stash drop") {
            _ = try await GitCLI.runChecked(["stash", "drop", "stash@{\(stash.index)}"], in: self.root)
        }
    }


    // MARK: - Conflicts

    func resolve(_ change: FileChange, useOurs: Bool) async {
        await perform("Resolve conflict") {
            _ = try await GitCLI.runChecked(["checkout", useOurs ? "--ours" : "--theirs", "--", change.path], in: self.root)
            _ = try await GitCLI.runChecked(["add", "--", change.path], in: self.root)
        }
    }

    func markResolved(_ change: FileChange) async {
        await perform("Mark resolved") {
            _ = try await GitCLI.runChecked(["add", "--", change.path], in: self.root)
        }
    }

    func openInEditor(_ change: FileChange) {
        let url = URL(fileURLWithPath: (root as NSString).appendingPathComponent(change.path))
        NSWorkspace.shared.open(url)
    }

    func continueOperation() async {
        guard let operation else { return }
        await perform("Continue") {
            let env = ["GIT_EDITOR": "true"]
            switch operation {
            case .merge:
                _ = try await GitCLI.runChecked(["merge", "--continue"], in: self.root, environment: env)
            case .rebase:
                _ = try await GitCLI.runChecked(["rebase", "--continue"], in: self.root, environment: env)
            case .cherryPick:
                _ = try await GitCLI.runChecked(["cherry-pick", "--continue"], in: self.root, environment: env)
            case .revert:
                _ = try await GitCLI.runChecked(["revert", "--continue"], in: self.root, environment: env)
            case .bisect:
                break
            }
        }
    }

    func abortOperation() async {
        guard let operation else { return }
        await perform("Abort") {
            switch operation {
            case .merge:
                _ = try await GitCLI.runChecked(["merge", "--abort"], in: self.root)
            case .rebase:
                _ = try await GitCLI.runChecked(["rebase", "--abort"], in: self.root)
            case .cherryPick:
                _ = try await GitCLI.runChecked(["cherry-pick", "--abort"], in: self.root)
            case .revert:
                _ = try await GitCLI.runChecked(["revert", "--abort"], in: self.root)
            case .bisect:
                _ = try await GitCLI.runChecked(["bisect", "reset"], in: self.root)
            }
        }
    }

    // MARK: - Interactive rebase

    struct RebaseStep: Identifiable {
        var hash: String
        var subject: String
        var action: String   // pick, squash, drop
        var id: String { hash }
    }

    func loadRebaseSteps(count: Int) async -> (base: String, steps: [RebaseStep]) {
        let out = (try? await GitCLI.runChecked(["log", "--reverse", "--format=%H%x00%s", "-n", "\(count)", "HEAD"], in: root)) ?? ""
        var steps: [RebaseStep] = []
        for line in out.split(separator: "\n") {
            let f = line.components(separatedBy: "\u{0}")
            guard f.count >= 2 else { continue }
            steps.append(RebaseStep(hash: f[0], subject: f[1], action: "pick"))
        }
        let base = (try? await GitCLI.runChecked(["rev-parse", "HEAD~\(steps.count)"], in: root))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (base ?? "", steps)
    }

    func runInteractiveRebase(base: String, steps: [RebaseStep]) async {
        guard !base.isEmpty else { return }
        let todo = steps.map { "\($0.action) \($0.hash)" }.joined(separator: "\n") + "\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gitscope-rebase-\(UUID().uuidString).txt")
        try? todo.write(to: url, atomically: true, encoding: .utf8)
        await perform("Interactive rebase") {
            _ = try await GitCLI.runChecked(["rebase", "-i", base], in: self.root,
                                            environment: ["GIT_SEQUENCE_EDITOR": "/bin/cp \(url.path)",
                                                          "GIT_EDITOR": "true"])
        }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - History rewriting

    func merge(_ branch: Branch) async {
        await perform("Merge \(branch.name)") {
            _ = try await GitCLI.run(["merge", "--no-edit", branch.name], in: self.root)
        }
    }

    func rebase(onto target: String) async {
        await perform("Rebase", refreshAfter: true) {
            _ = try await GitCLI.runChecked(["rebase", target], in: self.root)
        }
    }

    func cherryPick(_ hash: String) async {
        await perform("Cherry-pick") {
            _ = try await GitCLI.run(["cherry-pick", hash], in: self.root)
        }
    }

    func revert(_ hash: String) async {
        await perform("Revert") {
            _ = try await GitCLI.run(["revert", "--no-edit", hash], in: self.root)
        }
    }

    func reset(to hash: String, mode: ResetMode) async {
        await perform("Reset") {
            _ = try await GitCLI.runChecked(["reset", mode.flag, hash], in: self.root)
        }
    }

    enum ResetMode: String, CaseIterable, Identifiable {
        case soft, mixed, hard
        var id: String { rawValue }
        var flag: String { "--\(rawValue)" }
        var label: String { rawValue.capitalized }
    }

    // MARK: - Worktrees

    func addWorktree(path: String, branch: String, createBranch: String?) async {
        await perform("Add worktree") {
            if let createBranch {
                _ = try await GitCLI.runChecked(["worktree", "add", "-b", createBranch, path, branch], in: self.root)
            } else {
                _ = try await GitCLI.runChecked(["worktree", "add", path, branch], in: self.root)
            }
        }
    }

    func updateSubmodules() async {
        await perform("Update submodules") {
            _ = try await GitCLI.runChecked(["submodule", "update", "--init", "--recursive"], in: self.root)
        }
    }

    func removeWorktree(_ worktree: Worktree) async {
        await perform("Remove worktree") {
            _ = try await GitCLI.runChecked(["worktree", "remove", worktree.path], in: self.root)
        }
    }

    // MARK: - Patches / external tools

    func patchText(for hash: String) async -> String? {
        if let text = try? await GitCLI.runChecked(["format-patch", "-1", "--stdout", hash], in: root) {
            return text
        }
        return try? await GitCLI.runChecked(["show", "--no-color", "--format=", hash], in: root)
    }

    func copyPatch(for hash: String) async {
        guard let text = await patchText(for: hash) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func savePatch(for hash: String) async {
        guard let text = await patchText(for: hash) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(String(hash.prefix(7))).patch"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func openInTerminal() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", root]
        try? process.run()
    }

    func openInFinder() {
        NSWorkspace.shared.selectFile(root, inFileViewerRootedAtPath: root)
    }

    func openFileInEditor(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: (root as NSString).appendingPathComponent(path)))
    }

    // MARK: - Helper

    @discardableResult
    private func perform(_ name: String, refreshAfter: Bool = true, _ action: @escaping () async throws -> Void) async -> Bool {
        isBusy = true
        busyMessage = name
        defer { isBusy = false; busyMessage = nil }
        do {
            try await action()
            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

enum PatchBuilder {
    /// Build a single-hunk patch that can be applied to the index (or reversed in the worktree).
    static func patch(path: String, hunk: DiffHunk, staged: Bool) -> String {
        var lines: [String] = []
        lines.append("diff --git a/\(path) b/\(path)")
        lines.append("--- a/\(path)")
        lines.append("+++ b/\(path)")
        lines.append(hunk.header)
        for line in hunk.lines {
            switch line.kind {
            case .added: lines.append("+" + line.text)
            case .removed: lines.append("-" + line.text)
            case .context, .meta: lines.append(" " + line.text)
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
