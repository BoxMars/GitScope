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
    @Published var showingSettings = false
    @Published var diffMode: DiffMode = .unified {
        didSet { persist() }
    }
    @Published var showSidebar = true
    @Published var appearance: Appearance = .system {
        didSet { persist() }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
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

    private var isLoadingPreferences = true

    init() {
        loadPersisted()
        restoreTabs()
        isLoadingPreferences = false
    }

    // MARK: - Persistence

    private enum Keys {
        static let repositories = "gitscope.repositories"
        static let tabs = "gitscope.tabs"
        static let active = "gitscope.active"
        static let diffMode = "gitscope.diffMode"
        static let showSidebar = "gitscope.showSidebar"
        static let appearance = "gitscope.appearance"
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
        if let raw = defaults.string(forKey: Keys.appearance), let value = Appearance(rawValue: raw) {
            appearance = value
        }
        for repo in repositories where sessions[repo.path] == nil {
            sessions[repo.path] = RepoSession(ref: repo)
        }
    }

    private func persist() {
        guard !isLoadingPreferences else { return }
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(repositories) {
            defaults.set(data, forKey: Keys.repositories)
        }
        defaults.set(tabs, forKey: Keys.tabs)
        defaults.set(activePath, forKey: Keys.active)
        defaults.set(diffMode.rawValue, forKey: Keys.diffMode)
        defaults.set(showSidebar, forKey: Keys.showSidebar)
        defaults.set(appearance.rawValue, forKey: Keys.appearance)

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
        Task { await loadSidebarMetadata() }
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

    /// Populate branch/dirty info for repositories that have not been opened yet.
    private func loadSidebarMetadata() async {
        for repo in repositories {
            guard let session = sessions[repo.path], !session.hasLoaded else { continue }
            await session.loadStatusOnly()
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
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
            return
        }
        guard let session = sessions[path] else { return }
        activePath = path
        if !tabs.contains(path) { tabs.append(path) }
        persist()
        if !session.hasLoaded {
            Task { await session.refresh(force: true) }
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

}
