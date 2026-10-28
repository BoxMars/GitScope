import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, TahoeUI.titlebarInset)
            Divider().overlay(Theme.subtleBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(app.repositories) { repo in
                        if let session = app.sessions[repo.path] {
                            RepositoryRow(repo: repo, session: session, isActive: app.activePath == repo.path)
                                .onTapGesture { app.activate(repo.path) }
                        }
                    }
                    if let session = app.activeSession {
                        Rectangle()
                            .fill(Theme.subtleBorder)
                            .frame(height: 1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        SidebarRepoSections(session: session)
                    }
                }
                .padding(.bottom, 12)
            }

            Divider().overlay(Theme.subtleBorder)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                Text("Repositories")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .windowDragArea()

            Button {
                app.openRepositoryPanel()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Add repository (⌘O)")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                app.openRepositoryPanel()
            } label: {
                Label("Add", systemImage: "plus.circle").font(.system(size: 10.5))
            }
            .buttonStyle(.plain)

            Button {
                app.showCloneSheet = true
            } label: {
                Label("Clone", systemImage: "arrow.down.circle").font(.system(size: 10.5))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                app.showingSettings = true
            } label: {
                Image(systemName: "gearshape").font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
}

private struct RepositoryRow: View {
    var repo: RepositoryRef
    @ObservedObject var session: RepoSession
    var isActive: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.22) : color.opacity(0.18))
                Text(String(repo.name.prefix(1)).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isActive ? Color.white : color)
            }
            .frame(width: 19, height: 19)

            VStack(alignment: .leading, spacing: 0) {
                Text(repo.name)
                    .font(.system(size: 12, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let branch = session.status.branch ?? session.currentBranch?.name {
                    Text(branch)
                        .font(.system(size: 10))
                        .foregroundStyle(isActive ? Color.white.opacity(0.78) : Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            if session.isDirty {
                Circle().fill(isActive ? Color.white : Color(hex: 0xF59E0B)).frame(width: 5, height: 5)
            }
            if session.isBusy {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? Theme.sidebarSelection : (hovering ? Color.primary.opacity(0.028) : Color.clear))
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Menu("Checkout branch") {
                ForEach(session.localBranches) { branch in
                    Button {
                        Task { await session.checkout(branch) }
                    } label: {
                        if branch.isCurrent { Label(branch.name, systemImage: "checkmark") }
                        else { Text(branch.name) }
                    }
                }
            }
            Divider()
            Button("Fetch") { Task { await session.fetch() } }
            Button("Pull") { Task { await session.pull() } }
            Button("Push") { Task { await session.push() } }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(repo.path, inFileViewerRootedAtPath: repo.path)
            }
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(repo.path, forType: .string)
            }
            Divider()
            Button("Remove from GitScope", role: .destructive) {
                AppModel.shared.removeRepository(repo.path)
            }
        }
    }

    private var color: Color {
        Theme.graphColor(abs(repo.path.hashValue) % Theme.graphColors.count)
    }
}

struct SidebarRepoSections: View {
    @ObservedObject var session: RepoSession
    @EnvironmentObject var app: AppModel
    @State private var showBranches = true
    @State private var showRemotes = false
    @State private var showTags = true
    @State private var showStashes = true
    @State private var showWorktrees = false
    @State private var showSubmodules = true
    private let maxRows = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                session.setMode(.history)
                if session.filterRef != nil {
                    Task { await session.setFilterRef(nil) }
                }
            } label: {
                HStack(spacing: 7) {
                    SidebarIcon(systemName: "clock", isActive: isHistorySelected)
                    Text("All Commits")
                        .font(.system(size: 11.5))
                        .foregroundStyle(isHistorySelected ? Color.white : Color.primary)
                    Spacer()
                    Text("\(session.commits.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isHistorySelected ? Color.white.opacity(0.75) : Color.secondary)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHistorySelected ? Theme.sidebarSelection : Color.clear)
                        .padding(.horizontal, 6)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                session.selectWorkingDirectory()
            } label: {
                HStack(spacing: 7) {
                    SidebarIcon(systemName: "square.and.pencil", isActive: isChangesSelected)
                    Text("Working Directory")
                        .font(.system(size: 11.5))
                        .foregroundStyle(isChangesSelected ? Color.white : Color.primary)
                    Spacer()
                    if !session.status.changes.isEmpty {
                        Text("\(session.status.changes.count)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isChangesSelected ? Color.white : Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(isChangesSelected ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.14),
                                        in: Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isChangesSelected ? Theme.sidebarSelection : Color.clear)
                        .padding(.horizontal, 6)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SidebarSection(title: "Branches", expanded: $showBranches, count: session.localBranches.count) {
                ForEach(session.localBranches.prefix(maxRows)) { branch in
                    SidebarRow(icon: "arrow.triangle.branch",
                               title: branch.name,
                               detail: aheadBehind(branch),
                               isActive: session.filterRef == branch.name,
                               isCurrent: branch.isCurrent,
                               accent: branch.isCurrent ? Color.accentColor : Theme.secondaryText)
                        .onTapGesture {
                            session.setMode(.history)
                            Task { await session.setFilterRef(branch.name) }
                        }
                        .contextMenu {
                            Button("Checkout") { Task { await session.checkout(branch) } }
                            Button("Rename…") { promptRename(branch: branch) }
                            Divider()
                            Button("Delete branch", role: .destructive) {
                                Task { await session.deleteBranch(branch, force: false) }
                            }
                            .disabled(branch.isCurrent)
                        }
                }
                if session.localBranches.count > maxRows {
                    moreRow("Show all \(session.localBranches.count) branches") { session.inspector = .refList("branches") }
                }
            }

            SidebarSection(title: "Remotes", expanded: $showRemotes, count: session.remoteBranches.count) {
                ForEach(session.remoteBranches.prefix(maxRows)) { branch in
                    SidebarRow(icon: "cloud",
                               title: branch.name,
                               detail: nil,
                               isActive: session.filterRef == branch.name,
                               isCurrent: false,
                               accent: Theme.secondaryText)
                        .onTapGesture {
                            session.setMode(.history)
                            Task { await session.setFilterRef(branch.name) }
                        }
                        .contextMenu {
                            Button("Checkout as local branch") { Task { await session.checkout(branch) } }
                        }
                }
                if session.remoteBranches.count > maxRows {
                    moreRow("Show all \(session.remoteBranches.count) remote branches") { session.inspector = .refList("remotes") }
                }
            }

            SidebarSection(title: "Tags", expanded: $showTags, count: session.tags.count) {
                ForEach(session.tags.prefix(maxRows)) { tag in
                    SidebarRow(icon: "tag",
                               title: tag.name,
                               detail: nil,
                               isActive: false,
                               isCurrent: false,
                               accent: Color(hex: 0xD97706))
                        .onTapGesture {
                            if let commit = session.commits.first(where: { $0.hash == tag.hash }) {
                                Task { await session.select(commit: commit) }
                            }
                        }
                        .contextMenu {
                            Button("Delete tag", role: .destructive) {
                                Task { await session.deleteTag(tag) }
                            }
                            Button("Copy name") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(tag.name, forType: .string)
                            }
                        }
                }
                if session.tags.count > maxRows {
                    moreRow("Show all \(session.tags.count) tags") { session.inspector = .refList("tags") }
                }
            }

            SidebarSection(title: "Stashes", expanded: $showStashes, count: session.stashes.count) {
                ForEach(session.stashes) { stash in
                    SidebarRow(icon: "tray.and.arrow.down",
                               title: stash.message,
                               detail: nil,
                               isActive: false,
                               isCurrent: false,
                               accent: Theme.secondaryText)
                        .onTapGesture { session.inspector = .stash(stash) }
                        .contextMenu {
                            Button("Apply") { Task { await session.stashApply(stash) } }
                            Button("Pop") { Task { await session.stashPop(stash) } }
                            Divider()
                            Button("Drop", role: .destructive) { Task { await session.stashDrop(stash) } }
                        }
                }
            }

            if !session.submodules.isEmpty {
                SidebarSection(title: "Submodules", expanded: $showSubmodules, count: session.submodules.count) {
                    ForEach(session.submodules) { module in
                        SidebarRow(icon: "square.stack.3d.down.right",
                                   title: module.path,
                                   detail: String(module.hash.prefix(7)),
                                   isActive: false,
                                   isCurrent: !module.isDirty,
                                   accent: Theme.secondaryText)
                            .onTapGesture { session.inspector = .submodules }
                    }
                }
            }

            SidebarSection(title: "Worktrees", expanded: $showWorktrees, count: session.worktrees.count) {
                ForEach(session.worktrees) { worktree in
                    SidebarRow(icon: "square.on.square",
                               title: worktree.name,
                               detail: worktree.branch,
                               isActive: false,
                               isCurrent: worktree.path == session.root,
                               accent: Theme.secondaryText)
                        .contextMenu {
                            Button("Open in GitScope") { app.open(path: worktree.path) }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(worktree.path, inFileViewerRootedAtPath: worktree.path)
                            }
                            if worktree.path != session.root {
                                Button("Remove worktree", role: .destructive) {
                                    Task { await session.removeWorktree(worktree) }
                                }
                            }
                        }
                }
            }
        }
    }

    private func moreRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 10.5))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 8))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isHistorySelected: Bool {
        session.mode == .history && session.filterRef == nil
    }

    private var isChangesSelected: Bool {
        session.mode == .changes
    }

    private func aheadBehind(_ branch: Branch) -> String? {
        var pieces: [String] = []
        if branch.ahead > 0 { pieces.append("↑\(branch.ahead)") }
        if branch.behind > 0 { pieces.append("↓\(branch.behind)") }
        return pieces.isEmpty ? nil : pieces.joined(separator: " ")
    }

    private func promptRename(branch: Branch) {
        let alert = NSAlert()
        alert.messageText = "Rename branch"
        alert.informativeText = "Rename “\(branch.name)” to:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = branch.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty {
                Task { await session.renameBranch(branch, to: newName) }
            }
        }
    }
}

struct SidebarIcon: View {
    var systemName: String
    var isActive: Bool = false
    var tint: Color = Theme.secondaryText

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.22) : Color.primary.opacity(0.055))
            Image(systemName: systemName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(isActive ? Color.white : tint)
        }
        .frame(width: 19, height: 19)
    }
}

struct SidebarRow: View {
    var icon: String
    var title: String
    var detail: String?
    var isActive: Bool
    var isCurrent: Bool
    var accent: Color
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            SidebarIcon(systemName: icon,
                        isActive: isActive,
                        tint: isCurrent ? Color.accentColor : Theme.secondaryText)
            Text(title)
                .font(.system(size: 11.5, weight: isCurrent ? .medium : .regular))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if isCurrent {
                Circle().fill(isActive ? Color.white : Color.accentColor).frame(width: 4, height: 4)
            }
            Spacer(minLength: 2)
            if let detail {
                Text(detail)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(isActive ? Color.white.opacity(0.7) : Color.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? Theme.sidebarSelection : (hovering ? Color.primary.opacity(0.028) : Color.clear))
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct SidebarSection<Content: View>: View {
    var title: String
    @Binding var expanded: Bool
    var count: Int
    @State private var autoCollapsed = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.tertiary)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Text("\(count)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                content()
            }
        }
        .padding(.top, 4)
        .onChange(of: count) { _, newValue in
            if !autoCollapsed && newValue > 15 {
                expanded = false
                autoCollapsed = true
            }
        }
    }
}
