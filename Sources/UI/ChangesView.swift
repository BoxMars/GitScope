import SwiftUI

struct ChangesListView: View {
    @ObservedObject var session: RepoSession
    @State private var message = ""
    @State private var amend = false
    @State private var stageAllFirst = true

    var body: some View {
        VStack(spacing: 0) {
            if let operation = session.operation {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: 0xD97706))
                    Text(operation.title)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button("Continue") { Task { await session.continueOperation() } }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5, weight: .medium))
                    Button("Abort") { Task { await session.abortOperation() } }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(hex: 0xDC2626))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color(hex: 0xD97706).opacity(0.10))
                Divider().overlay(Theme.subtleBorder)
            }
            if session.status.changes.isEmpty {
                EmptyHint(icon: "checkmark.circle", title: "No changes",
                          subtitle: "The working directory is clean.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if session.status.hasConflicts {
                            groupHeader("Conflicts", count: session.status.changes.filter { $0.kind == .unmerged }.count, staged: false)
                            ForEach(session.status.changes.filter { $0.kind == .unmerged }) { change in
                                ConflictRow(change: change, session: session)
                            }
                        }
                        if !session.status.stagedChanges.isEmpty {
                            groupHeader("Staged", count: session.status.stagedChanges.count, staged: true)
                            ForEach(session.status.stagedChanges) { change in
                                ChangeRow(change: change, session: session)
                            }
                        }
                        if !session.status.unstagedChanges.isEmpty {
                            groupHeader("Changes", count: session.status.unstagedChanges.count, staged: false)
                            ForEach(session.status.unstagedChanges) { change in
                                ChangeRow(change: change, session: session)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .softTopEdge()
            }
            Divider().overlay(Theme.subtleBorder)
            composer
        }
        .background(Theme.contentBackground)
    }


    private func groupHeader(_ title: String, count: Int, staged: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(staged ? "Unstage all" : "Stage all") {
                Task {
                    if staged { await session.unstageAll() } else { await session.stageAll() }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text("Commit message")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 7)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .font(.system(size: 11.5))
                    .scrollContentBackground(.hidden)
                    .padding(2)
                    .frame(height: 62)
                    .background(Theme.editorBackground, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border, lineWidth: 0.5))
            }

            HStack(spacing: 8) {
                Toggle("Amend", isOn: $amend)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10.5))
                Toggle("Stage all", isOn: $stageAllFirst)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10.5))
                Spacer()
                Button {
                    let text = message
                    Task {
                        let ok = await session.commit(message: text, amend: amend, stageAllFirst: stageAllFirst)
                        if ok {
                            message = ""
                            amend = false
                        }
                    }
                } label: {
                    Label(amend ? "Amend Commit" : "Commit", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || (!stageAllFirst && session.status.stagedChanges.isEmpty))
            }
        }
        .padding(10)
        .background(Theme.toolbarBackground)
    }
}

struct ConflictRow: View {
    var change: FileChange
    @ObservedObject var session: RepoSession

    var body: some View {
        HStack(spacing: 7) {
            StatusGlyph(kind: .unmerged)
            Text(change.path)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button("Ours") { Task { await session.resolve(change, useOurs: true) } }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .help("Take our version and mark resolved")
            Button("Theirs") { Task { await session.resolve(change, useOurs: false) } }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .help("Take their version and mark resolved")
            Button("Mark resolved") { Task { await session.markResolved(change) } }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .contextMenu {
            Button("Open in editor") { session.openInEditor(change) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile((session.root as NSString).appendingPathComponent(change.path),
                                              inFileViewerRootedAtPath: session.root)
            }
        }
    }
}

struct ChangeRow: View {
    var change: FileChange
    @ObservedObject var session: RepoSession
    @State private var hovering = false

    private var isSelected: Bool { session.selectedChange?.id == change.id }

    var body: some View {
        HStack(spacing: 7) {
            StatusGlyph(kind: change.kind)
            VStack(alignment: .leading, spacing: 1) {
                Text(change.fileName)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                if !change.directory.isEmpty {
                    Text(change.directory)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            if hovering {
                Button {
                    Task {
                        if change.staged {
                            await session.unstage(change)
                        } else {
                            await session.stage(change)
                        }
                    }
                } label: {
                    Image(systemName: change.staged ? "minus.circle" : "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(change.staged ? "Unstage" : "Stage")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(isSelected ? Theme.selectionBackground : (hovering ? Color.primary.opacity(0.035) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            Task { await session.selectChange(change) }
        }
        .onTapGesture(count: 2) {
            session.openFileInEditor(change.path)
        }
        .contextMenu {
            if change.staged {
                Button("Unstage") { Task { await session.unstage(change) } }
            } else {
                Button("Stage") { Task { await session.stage(change) } }
                Button("Discard changes", role: .destructive) {
                    Task { await session.discard(change) }
                }
            }
            Divider()
            Button("Blame") { session.inspector = .blame(change.path) }
            Button("File history") { session.inspector = .fileHistory(change.path) }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile((session.root as NSString).appendingPathComponent(change.path),
                                              inFileViewerRootedAtPath: session.root)
            }
        }
    }
}
