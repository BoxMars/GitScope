import SwiftUI
import AppKit

struct CommitDetailView: View {
    @ObservedObject var session: RepoSession
    var commit: Commit

    @EnvironmentObject var app: AppModel

    @State private var showBody = false
    @State private var showFiles = true
    @State private var tagSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.subtleBorder)
            filesHeader
            if session.detailTab == .tree {
                treeList
                Divider().overlay(Theme.subtleBorder)
                CodeView(text: session.treeContent,
                         path: session.treeSelection,
                         isBinary: session.treeIsBinary)
            } else {
                if showFiles {
                    fileList
                    Divider().overlay(Theme.subtleBorder)
                }
                FileDiffView(diff: session.diff,
                             file: session.selectedFile,
                             isLoading: session.isDiffLoading,
                             mode: app.diffMode,
                             imagePair: session.imagePair,
                             onModeChange: { app.diffMode = $0 })
            }
        }
        .background(Theme.editorBackground)
        .sheet(isPresented: $tagSheet) {
            NewTagSheet(session: session, targetHash: commit.hash)
        }
        .onChange(of: session.detailTab) { _, tab in
            if tab == .tree {
                Task { await session.loadTree() }
            }
        }
        .onAppear {
            if session.detailTab == .tree {
                Task { await session.loadTree() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Avatar(name: commit.author, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.subject.isEmpty ? "(no message)" : commit.subject)
                        .font(.system(size: 13.5, weight: .semibold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        Text(commit.author)
                            .fontWeight(.medium)
                        Text("committed \(commit.formattedDate)")
                        Text("·")
                        Text(commit.shortHash)
                            .font(Theme.monoSmall)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ToolbarButton(icon: "arrow.triangle.branch", help: "Checkout this commit") {
                        Task { await session.checkoutCommit(commit.hash) }
                    }
                    ToolbarButton(icon: "tag", help: "Create tag here") {
                        tagSheet = true
                    }
                    ToolbarButton(icon: "doc.on.doc", help: "Copy commit hash") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(commit.hash, forType: .string)
                    }
                }
            }

            if !commit.refs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(commit.refs) { ref in
                            RefBadge(ref: ref).fixedSize()
                        }
                    }
                }
                .frame(height: 18)
                .padding(.leading, 34)
            }

            if !commit.body.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(showBody ? nil : 2)
                        .textSelection(.enabled)
                    if commit.body.count > 120 {
                        Button(showBody ? "Show less" : "Show more") {
                            withAnimation(.easeInOut(duration: 0.15)) { showBody.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.contentBackground)
    }

    private var filesHeader: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { showFiles.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(showFiles ? 0 : -90))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 10)

            Text("\(session.commitFiles.count) file\(session.commitFiles.count == 1 ? "" : "s") changed")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Picker("", selection: $session.detailTab) {
                ForEach(RepoSession.CommitDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .scaleEffect(0.9)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Theme.toolbarBackground)
    }

    private var treeList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(session.treeFiles, id: \.self) { path in
                    HStack(spacing: 7) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(session.treeSelection == path ? Theme.selectionBackground : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await session.selectTreeFile(path) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: min(CGFloat(session.treeFiles.count) * 24 + 6, 150))
        .background(Theme.contentBackground)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(session.commitFiles) { file in
                        fileRow(file)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: min(CGFloat(max(session.commitFiles.count, 1)) * 24, 120))
            .background(Theme.contentBackground)
        }
    }

    private func fileRow(_ file: FileChange) -> some View {
        HStack(spacing: 7) {
            StatusGlyph(kind: file.kind)
            Text(file.path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            if let old = file.oldPath, old != file.path {
                Text("← \(old)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(session.selectedFile?.path == file.path ? Theme.selectionBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await session.selectCommitFile(file) }
        }
        .onTapGesture(count: 2) {
            session.openFileInEditor(file.path)
        }
        .contextMenu {
            Button("Open in default editor") {
                NSWorkspace.shared.open(URL(fileURLWithPath: (session.root as NSString).appendingPathComponent(file.path)))
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile((session.root as NSString).appendingPathComponent(file.path),
                                              inFileViewerRootedAtPath: session.root)
            }
            Button("Blame") { session.inspector = .blame(file.path) }
            Button("File history") { session.inspector = .fileHistory(file.path) }
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
    }
}
