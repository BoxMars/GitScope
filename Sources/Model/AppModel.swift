import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var repositories: [RepositoryRef] = []
    @Published var tabs: [String] = []
    @Published var activePath: String?
    @Published var sessions: [String: RepoSession] = [:]
    @Published var isAddingRepository = false
    @Published var showCloneSheet = false
    @Published var globalError: String?
    @Published var sidebarSection: SidebarSection = .history
    @Published var showingSettings = false
    @Published var diffMode: DiffMode = .unified
    @Published var showSidebar = true
    @Published var showDetail = true

    enum SidebarSection: String, CaseIterable, Identifiable {
        case history, changes, branches, stashes, worktrees, blame, reflog
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .history: return "clock"
            case .changes: return "square.and.pencil"
            case .branches: return "arrow.triangle.branch"
            case .stashes: return "tray.and.arrow.down"
            case .worktrees: return "square.on.square"
            case .blame: return "person.text.rectangle"
            case .reflog: return "list.bullet.rectangle"
            }
        }
    }

    enum DiffMode: String, CaseIterable, Identifiable {
        case unified, sideBySide
        var id: String { rawValue }
        var title: String { self == .unified ? "Unified" : "Side by Side" }
        var icon: String { self == .unified ? "rectangle.split.1x2" : "rectangle.split.2x1" }
    }

    var activeSession: RepoSession? {
        guard let activePath else { return nil }
        return sessions[activePath]
    }

    init() {
        loadPersisted()
        restoreTabs()
    }

    // MARK: - Persistence

    private enum Keys {
        static let repositories = "gitscope.repositories"
        static let tabs = "gitscope.tabs"
        static let active = "gitscope.active"
        static let diffMode = "gitscope.diffMode"
        static let showSidebar = "gitscope.showSidebar"
    }

    private func loadPersisted() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.repositories),
           let decoded = try? JSONDecoder().decode([RepositoryRef].self, from: data) {
            repositories = decoded
        }
        tabs = defaults.stringArray(forKey: Keys.tabs) ?? []
        activePath = defaults.string(forKey: Keys.active)
        if let raw = defaults.string(forKey: Keys.diffMode), let mode = DiffMode(rawValue: raw) {
            diffMode = mode
        }
        if defaults.object(forKey: Keys.showSidebar) != nil {
            showSidebar = defaults.bool(forKey: Keys.showSidebar)
        }
        for repo in repositories where sessions[repo.path] == nil {
            sessions[repo.path] = RepoSession(ref: repo)
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(repositories) {
            defaults.set(data, forKey: Keys.repositories)
        }
        defaults.set(tabs, forKey: Keys.tabs)
        defaults.set(activePath, forKey: Keys.active)
        defaults.set(diffMode.rawValue, forKey: Keys.diffMode)
        defaults.set(showSidebar, forKey: Keys.showSidebar)
    }

    private func restoreTabs() {
        let validTabs = tabs.filter { path in
            repositories.contains(where: { $0.path == path })
        }
        tabs = validTabs
        for path in tabs {
            _ = session(for: path)
        }
        if activePath == nil || sessions[activePath!] == nil {
            activePath = tabs.first ?? repositories.first?.path
        }
        if let session = activeSession {
            Task { await session.refresh(force: true) }
            if tabs.isEmpty { tabs = [session.id] }
        }
    }

    // MARK: - Repositories

    @discardableResult
    func open(path: String, name: String? = nil) -> RepoSession {
        let ref = repositories.first(where: { $0.path == path }) ?? RepositoryRef(path: path, name: name)
        if !repositories.contains(where: { $0.path == path }) {
            repositories.append(ref)
        }
        let session = sessions[path] ?? RepoSession(ref: ref)
        sessions[path] = session
        if !tabs.contains(path) { tabs.append(path) }
        activePath = path
        persist()
        Task { await session.refresh(force: true) }
        return session
    }

    func openRepositoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose one or more Git repositories"
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { await addRepositories(urls: urls) }
        }
    }

    func addRepository(url: URL) async {
        let path = url.path
        do {
            let info = try await GitRepo.info(at: path)
            let ref = RepositoryRef(path: info.root)
            if !repositories.contains(where: { $0.path == ref.path }) {
                repositories.append(ref)
            }
            open(path: ref.path)
        } catch {
            globalError = "\(url.lastPathComponent) is not a git repository."
        }
    }

    func addRepositories(urls: [URL]) async {
        for url in urls {
            await addRepository(url: url)
        }
    }

    func session(for path: String) -> RepoSession? {
        if let s = sessions[path] { return s }
        guard let ref = repositories.first(where: { $0.path == path }) else { return nil }
        let s = RepoSession(ref: ref)
        sessions[path] = s
        Task { await s.refresh(force: true) }
        return s
    }

    func activate(_ path: String) {
        if sessions[path] == nil {
            guard repositories.contains(where: { $0.path == path }) else { return }
            _ = open(path: path)
        } else {
            activePath = path
            if !tabs.contains(path) { tabs.append(path) }
            persist()
        }
    }

    func closeTab(_ path: String) {
        tabs.removeAll { $0 == path }
        sessions[path] = nil
        if activePath == path {
            activePath = tabs.last ?? repositories.first?.path
            if let activePath, sessions[activePath] == nil {
                _ = open(path: activePath)
            }
        }
        persist()
    }

    func removeRepository(_ path: String) {
        tabs.removeAll { $0 == path }
        sessions[path] = nil
        repositories.removeAll { $0.path == path }
        if activePath == path { activePath = nil }
        persist()
    }

    func moveTab(from source: Int, to destination: Int) {
        guard source != destination, tabs.indices.contains(source) else { return }
        let item = tabs.remove(at: source)
        tabs.insert(item, at: min(destination, tabs.count))
        persist()
    }
}
