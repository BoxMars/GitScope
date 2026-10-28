import SwiftUI
import AppKit

@main
struct GitScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppModel.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(app)
                .frame(minWidth: 1060, minHeight: 680)
        }
        .defaultSize(width: 1440, height: 880)
        .defaultPosition(.center)
        .commands {
            AppCommands(app: app)
        }
    }
}

enum SnapshotWriter {
    @MainActor
    static func write(to path: String) {
        let window = NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isSheet && $0.isVisible })
            ?? NSApp.windows.first(where: { $0.canBecomeMain })
        guard let window, let view = window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--open"), index + 1 < args.count {
            let path = args[index + 1]
            let select = args.firstIndex(of: "--select").flatMap { i in
                i + 1 < args.count ? args[i + 1] : nil
            }
            Task { @MainActor in
                await AppModel.shared.addRepository(url: URL(fileURLWithPath: path))
                guard let select, let session = AppModel.shared.activeSession else { return }
                for _ in 0..<50 where session.commits.isEmpty {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if let commit = session.commits.first(where: { $0.hash.hasPrefix(select) }) {
                    await session.select(commit: commit)
                }
            }
        }
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            let snapshotPath = args[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                SnapshotWriter.write(to: snapshotPath)
            }
        }
        if args.contains("--side-by-side") {
            AppModel.shared.diffMode = .sideBySide
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct AppCommands: Commands {
    @ObservedObject var app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Repository…") { app.openRepositoryPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Clone Repository…") { app.showCloneSheet = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {}

        CommandMenu("Repository") {
            Button("Refresh") {
                if let session = app.activeSession { Task { await session.refresh(force: true) } }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(app.activeSession == nil)

            Divider()

            Button("Fetch") {
                if let session = app.activeSession { Task { await session.fetch() } }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(app.activeSession == nil)

            Button("Pull") {
                if let session = app.activeSession { Task { await session.pull() } }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(app.activeSession == nil)

            Button("Push") {
                if let session = app.activeSession { Task { await session.push() } }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(app.activeSession == nil)

            Divider()

            Button("Stash changes") {
                if let session = app.activeSession { Task { await session.stashPush(message: nil) } }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(app.activeSession == nil)
        }

        CommandGroup(after: .sidebar) {
            Button(app.showSidebar ? "Hide Sidebar" : "Show Sidebar") {
                withAnimation(.easeInOut(duration: 0.15)) { app.showSidebar.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Toggle Diff Layout") {
                app.diffMode = app.diffMode == .unified ? .sideBySide : .unified
            }
            .keyboardShortcut("d", modifiers: [.command, .option])

            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("GitScope Help") {
                NSWorkspace.shared.open(URL(string: "https://git-scm.com/docs")!)
            }
        }
    }
}
