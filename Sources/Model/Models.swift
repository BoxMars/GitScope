import Foundation

// MARK: - Repositories

struct RepositoryRef: Identifiable, Hashable, Codable {
    var path: String
    var name: String
    var group: String?
    var id: String { path }

    init(path: String, name: String? = nil, group: String? = nil) {
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.group = group
    }
}

struct RepoInfo: Hashable {
    var root: String
    var gitDir: String
    var commonDir: String
    var isBare: Bool
    var isWorktree: Bool
    var isSubmodule: Bool
    var superproject: String?
}

// MARK: - Refs

enum RefKind: String, Hashable {
    case localBranch
    case remoteBranch
    case tag
    case head
}

struct RefLabel: Identifiable, Hashable {
    var name: String
    var kind: RefKind
    var isCurrent: Bool = false
    var id: String { "\(kind.rawValue):\(name)" }

    var displayName: String {
        switch kind {
        case .localBranch: return name
        case .remoteBranch: return name
        case .tag: return name
        case .head: return name
        }
    }
}

// MARK: - Commit

struct Commit: Identifiable, Hashable {
    var hash: String
    var parents: [String]
    var author: String
    var authorEmail: String
    var authorDate: Date
    var committer: String
    var committerDate: Date
    var subject: String
    var body: String
    var refs: [RefLabel]

    // Rendering info, filled in by the graph layout.
    var lane: Int = 0
    var laneColor: Int = 0

    var id: String { hash }
    var shortHash: String { String(hash.prefix(7)) }

    var isMerge: Bool { parents.count > 1 }

    var relativeAuthorDate: String {
        Self.relativeFormatter.localizedString(for: authorDate, relativeTo: Date())
    }

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var formattedDate: String { Self.dateFormatter.string(from: authorDate) }
}

struct Branch: Identifiable, Hashable {
    var name: String          // short name, e.g. "main" or "origin/main"
    var fullName: String
    var hash: String
    var isRemote: Bool
    var isCurrent: Bool
    var upstream: String?
    var ahead: Int
    var behind: Int
    var lastCommitDate: Date?

    var id: String { fullName }

    var remoteName: String? {
        guard isRemote, let slash = name.firstIndex(of: "/") else { return nil }
        return String(name[..<slash])
    }

    var shortName: String {
        guard isRemote, let slash = name.firstIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }
}

struct Tag: Identifiable, Hashable {
    var name: String
    var hash: String
    var message: String
    var date: Date?
    var id: String { name }
}

struct Stash: Identifiable, Hashable {
    var index: Int
    var hash: String
    var message: String
    var date: Date?
    var id: String { "stash@\(index)" }
}

struct Submodule: Identifiable, Hashable {
    var path: String
    var hash: String
    var status: String
    var id: String { path }
    var isDirty: Bool { status != " " && status != "-" }
}

struct Worktree: Identifiable, Hashable {
    var path: String
    var head: String
    var branch: String?
    var isBare: Bool
    var isDetached: Bool
    var isLocked: Bool
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

// MARK: - Changes

enum ChangeKind: String, Hashable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case typeChanged = "T"
    case unmerged = "U"
    case untracked = "?"

    var symbol: String { rawValue }

    var label: String {
        switch self {
        case .added, .untracked: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        case .typeChanged: return "Type changed"
        case .unmerged: return "Conflict"
        }
    }
}

struct FileChange: Identifiable, Hashable {
    var path: String
    var oldPath: String?
    var kind: ChangeKind
    var staged: Bool = false
    var additions: Int = 0
    var deletions: Int = 0
    var isBinary: Bool = false
    var isSubmodule: Bool = false

    var id: String { (oldPath ?? path) + "->" + path + (staged ? ":s" : ":u") }

    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

struct WorkingStatus: Hashable {
    var branch: String?
    var upstream: String?
    var ahead: Int = 0
    var behind: Int = 0
    var detached: Bool = false
    var changes: [FileChange] = []

    var stagedChanges: [FileChange] { changes.filter { $0.staged && $0.kind != .unmerged } }
    var unstagedChanges: [FileChange] { changes.filter { !$0.staged && $0.kind != .unmerged } }
    var hasConflicts: Bool { changes.contains { $0.kind == .unmerged } }
    var isEmpty: Bool { changes.isEmpty }
}

// MARK: - Diff

enum DiffLineKind {
    case context
    case added
    case removed
    case meta
}

struct DiffLine: Identifiable, Hashable {
    var kind: DiffLineKind
    var oldNumber: Int?
    var newNumber: Int?
    var text: String

    var id: String { "\(oldNumber ?? -1)-\(newNumber ?? -1)-\(kind)" }
}

struct DiffHunk: Identifiable, Hashable {
    var header: String
    var oldStart: Int
    var oldCount: Int
    var newStart: Int
    var newCount: Int
    var lines: [DiffLine]

    var id: String { header + "\(oldStart)" }
}

struct FileDiff: Hashable {
    var path: String
    var oldPath: String?
    var hunks: [DiffHunk]
    var isBinary: Bool = false
    var rawText: String = ""
    var truncated: Bool = false
}

// MARK: - Side by side rows

struct SideBySideRow: Identifiable {
    enum Kind {
        case context
        case added
        case removed
        case replaced
        case spacer
        case hunkHeader
    }

    var id: Int
    var kind: Kind
    var leftNumber: Int?
    var leftText: String?
    var rightNumber: Int?
    var rightText: String?
    var header: String?
}
