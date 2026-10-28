import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ZStack {
            AppBackdrop()

            HStack(spacing: 0) {
                if app.showSidebar {
                    SidebarView()
                        .frame(width: Theme.sidebarWidth)
                        .background(.regularMaterial)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(Theme.border).frame(width: 1)
                        }
                }

                VStack(spacing: 0) {
                    if let session = app.activeSession {
                        RepoView(session: session)
                    } else {
                        WelcomeView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.contentBackground)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(WindowChromeConfigurator(appearance: app.appearance))
        .preferredColorScheme(app.appearance.colorScheme)
        .frame(minWidth: 1060, minHeight: 680)
        .sheet(isPresented: $app.showCloneSheet) {
            CloneSheet(app: app)
        }
        .sheet(isPresented: $app.showingSettings) {
            SettingsSheet()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { app.globalError != nil },
            set: { if !$0 { app.globalError = nil } }
        )) {
            Button("OK") { app.globalError = nil }
        } message: {
            Text(app.globalError ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if let session = app.activeSession {
                Task { await session.refresh(force: false) }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await app.addRepository(url: url)
                }
            }
        }
        return true
    }
}

struct RepoView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: RepoSession

    var body: some View {
        CanvasSplitView(initialWidth: 520) {
            leftPane
        } right: {
            detailPane
        }
        .padding(.top, 2)
        .background(Theme.contentBackground)
        .background(InspectorSheets(session: session))
        .sheet(isPresented: $session.showRebaseSheet) {
            InteractiveRebaseSheet(session: session)
        }
        .sheet(isPresented: $session.showWorktreeSheet) {
            NewWorktreeSheet(session: session)
        }
        .alert("Git error", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var leftPane: some View {
        switch session.mode {
        case .changes:
            ChangesListView(session: session)
        case .history:
            HistoryListView(session: session)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if session.mode == .changes {
            FileDiffView(diff: session.diff,
                         file: session.selectedChange,
                         isLoading: session.isDiffLoading,
                         mode: app.diffMode,
                         imagePair: session.imagePair,
                         stagedContext: session.selectedChange?.staged ?? false,
                         onStageHunk: (session.selectedChange?.staged == false && session.selectedChange?.kind != .unmerged) ? { hunk in
                             guard let change = session.selectedChange else { return }
                             Task { await session.stageHunk(path: change.path, hunk: hunk, staged: false) }
                         } : nil,
                         onUnstageHunk: (session.selectedChange?.staged == true) ? { hunk in
                             guard let change = session.selectedChange else { return }
                             Task { await session.stageHunk(path: change.path, hunk: hunk, staged: true) }
                         } : nil,
                         onStageFile: {
                             guard let change = session.selectedChange else { return }
                             Task { await session.stage(change) }
                         },
                         onUnstageFile: {
                             guard let change = session.selectedChange else { return }
                             Task { await session.unstage(change) }
                         },
                         onDiscardFile: (session.selectedChange?.kind == .unmerged) ? nil : {
                             guard let change = session.selectedChange else { return }
                             Task { await session.discard(change) }
                         },
                         onModeChange: { app.diffMode = $0 },
                         ignoreWhitespace: session.ignoreWhitespace,
                         onToggleWhitespace: { session.ignoreWhitespace.toggle() })
        } else if let commit = session.selectedCommit {
            CommitDetailView(session: session, commit: commit)
        } else {
            EmptyHint(icon: "clock", title: "No commit selected", subtitle: nil)
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.7))
            Text("GitScope")
                .font(.system(size: 22, weight: .semibold))
            Text("A fast local Git browser for all your repositories.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    app.openRepositoryPanel()
                } label: {
                    Label("Open Repository", systemImage: "folder")
                }
                .controlSize(.large)

                Button {
                    app.showCloneSheet = true
                } label: {
                    Label("Clone Repository", systemImage: "arrow.down.circle")
                }
                .controlSize(.large)
            }
            .padding(.top, 6)

            if !app.repositories.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 2)
                    ForEach(app.repositories.prefix(6)) { repo in
                        Button {
                            app.open(path: repo.path)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10))
                                Text(repo.name)
                                    .font(.system(size: 11.5))
                                Text(repo.path)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 360)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences").font(.system(size: 15, weight: .semibold))

            HStack {
                Text("Appearance").font(.system(size: 12))
                Spacer()
                Picker("", selection: $app.appearance) {
                    ForEach(AppModel.Appearance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Default diff layout").font(.system(size: 12))
                Spacer()
                Picker("", selection: $app.diffMode) {
                    ForEach(AppModel.DiffMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Show sidebar on launch").font(.system(size: 12))
                Spacer()
                Toggle("", isOn: $app.showSidebar).labelsHidden()
            }

            Divider()

            HStack {
                Text("Git binary").font(.system(size: 12))
                Spacer()
                Text(GitCLI.executable)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("GitScope \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
