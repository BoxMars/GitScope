import SwiftUI
import AppKit

struct InspectorSheets: View {
    @ObservedObject var session: RepoSession

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $session.inspector) { inspector in
                switch inspector {
                case .blame(let path):
                    BlameSheet(session: session, path: path)
                case .fileHistory(let path):
                    FileHistorySheet(session: session, path: path)
                case .reflog:
                    ReflogSheet(session: session)
                case .submodules:
                    SubmodulesSheet(session: session)
                case .stash(let stash):
                    StashSheet(session: session, stash: stash)
                case .refList(let kind):
                    RefListSheet(session: session, kind: kind)
                }
            }
    }
}

struct BlameSheet: View {
    @ObservedObject var session: RepoSession
    var path: String

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [GitRepo.BlameLine] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var hovered: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .foregroundStyle(.secondary)
                Text("Blame")
                    .font(.system(size: 13, weight: .semibold))
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.toolbarBackground)

            Divider().overlay(Theme.border)

            if let errorText {
                EmptyHint(icon: "exclamationmark.triangle", title: "Unable to blame", subtitle: errorText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            row(index: index, line: line)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            do {
                lines = try await GitRepo.blame(path: path, at: session.root)
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func blockColor(_ index: Int) -> Color {
        guard lines.indices.contains(index) else { return .clear }
        var block = 0
        var i = index
        while i > 0, lines[i - 1].hash == lines[i].hash {
            i -= 1
            block += 1
        }
        // Group consecutive identical blames into a stable pseudo-random tint.
        var hasher = Hasher()
        hasher.combine(lines[index].hash)
        let value = abs(hasher.finalize())
        return Theme.graphColor(value % Theme.graphColors.count).opacity(0.07)
    }

    private func row(index: Int, line: GitRepo.BlameLine) -> some View {
        HStack(spacing: 0) {
            Text("\(line.lineNumber)")
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, 8)
                .foregroundStyle(.tertiary)
            Text(String(line.hash.prefix(8)))
                .frame(width: 68, alignment: .leading)
                .foregroundStyle(Color.accentColor)
            Text(line.author)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
            Text(Commit.dateFormatter.string(from: line.date))
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(.tertiary)
            Text(line.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.adaptive(light: 0x3A3A3C, dark: 0xD6D6D8))
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.vertical, 1)
        .background(hovered == index ? Theme.selectionBackground : blockColor(index))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
        .onTapGesture(count: 2) {
            let hash = line.hash
            dismiss()
            Task {
                if let commit = session.commits.first(where: { $0.hash == hash }) {
                    await session.select(commit: commit)
                }
            }
        }
        .contextMenu {
            Button("Copy commit hash") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.hash, forType: .string)
            }
            Button("Show commit") {
                let hash = line.hash
                dismiss()
                Task {
                    if let commit = session.commits.first(where: { $0.hash == hash }) {
                        await session.select(commit: commit)
                    }
                }
            }
        }
    }
}

struct FileHistorySheet: View {
    @ObservedObject var session: RepoSession
    var path: String

    @Environment(\.dismiss) private var dismiss
    @State private var commits: [Commit] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                Text("History").font(.system(size: 13, weight: .semibold))
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.toolbarBackground)

            Divider().overlay(Theme.border)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(commits) { commit in
                        HStack(spacing: 8) {
                            Avatar(name: commit.author, size: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(commit.subject).font(.system(size: 12)).lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(commit.author)
                                    Text("·")
                                    Text(commit.relativeAuthorDate)
                                    Text("·")
                                    Text(commit.shortHash).font(Theme.monoSmall)
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismiss()
                            Task { await session.select(commit: commit) }
                        }
                    }
                }
            }
        }
        .frame(width: 560, height: 520)
        .task {
            commits = (try? await GitRepo.log(at: session.root, limit: 300, path: path)) ?? []
            isLoading = false
        }
    }
}

struct ReflogSheet: View {
    @ObservedObject var session: RepoSession
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [GitRepo.ReflogEntry] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(.secondary)
                Text("Reflog").font(.system(size: 13, weight: .semibold))
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.toolbarBackground)

            Divider().overlay(Theme.border)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Text(entry.hash)
                                .font(Theme.monoSmall)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 62, alignment: .leading)
                            Text(entry.selector)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(entry.message)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Checkout this commit") {
                                let hash = entry.hash
                                dismiss()
                                Task { await session.checkoutCommit(hash) }
                            }
                            Button("Copy hash") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.hash, forType: .string)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 760, height: 560)
        .task {
            entries = (try? await GitRepo.reflog(at: session.root)) ?? []
            isLoading = false
        }
    }
}

struct StashSheet: View {
    @ObservedObject var session: RepoSession
    var stash: Stash
    @Environment(\.dismiss) private var dismiss
    @State private var files: [FileDiff] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down").foregroundStyle(.secondary)
                Text("stash@{\(stash.index)}").font(.system(size: 12, design: .monospaced))
                Text(stash.message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("Apply") { Task { await session.stashApply(stash); dismiss() } }
                Button("Pop") { Task { await session.stashPop(stash); dismiss() } }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Theme.toolbarBackground)

            Divider().overlay(Theme.border)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(files, id: \.path) { file in
                        Text(file.path)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.hunkBackground)
                        ForEach(file.hunks) { hunk in
                            Text(hunk.header)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .frame(height: 20)
                            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                HStack(spacing: 0) {
                                    Text(line.kind == .added ? "+" : (line.kind == .removed ? "-" : " "))
                                        .frame(width: 14)
                                        .foregroundStyle(line.kind == .added ? Color(hex: 0x16A34A) : (line.kind == .removed ? Color(hex: 0xDC2626) : .clear))
                                    Text(line.text)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 18)
                                .background(line.kind == .added ? Theme.diffAddedBackground : (line.kind == .removed ? Theme.diffRemovedBackground : Color.clear))
                            }
                        }
                        Divider()
                    }
                }
            }
        }
        .frame(width: 820, height: 600)
        .task {
            let patch = (try? await GitCLI.runChecked(["stash", "show", "-p", "--no-color", "stash@{\(stash.index)}"], in: session.root)) ?? ""
            files = DiffParser.parse(patch)
            isLoading = false
        }
    }
}

struct SubmodulesSheet: View {
    @ObservedObject var session: RepoSession
    @Environment(\.dismiss) private var dismiss
    @State private var modules: [(path: String, hash: String, status: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Submodules").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Update all") {
                    Task { await session.updateSubmodules() }
                }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            .background(Theme.toolbarBackground)
            Divider()
            if modules.isEmpty {
                EmptyHint(icon: "square.stack.3d.down.right", title: "No submodules", subtitle: nil)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(modules, id: \.path) { module in
                            HStack(spacing: 8) {
                                Text(module.status)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(module.status == "-" ? Color.secondary : Color.accentColor)
                                    .frame(width: 14)
                                Text(module.path).font(.system(size: 11.5, design: .monospaced))
                                Spacer()
                                Text(String(module.hash.prefix(8)))
                                    .font(Theme.monoSmall)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                        }
                    }
                }
            }
        }
        .frame(width: 560, height: 400)
        .task {
            modules = (try? await GitRepo.submodules(at: session.root)) ?? []
        }
    }
}

struct RefListSheet: View {
    @ObservedObject var session: RepoSession
    var kind: String   // "tags", "remotes", "branches"
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(kind.capitalized).font(.system(size: 13, weight: .semibold))
                TextField("Filter", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            .background(Theme.toolbarBackground)
            Divider().overlay(Theme.border)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.id) { item in
                        HStack(spacing: 8) {
                            Image(systemName: kind == "tags" ? "tag" : (kind == "remotes" ? "cloud" : "arrow.triangle.branch"))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(item.name).font(.system(size: 11.5, design: .monospaced))
                            Spacer()
                            Text(item.detail).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .contextMenu {
                            Button("Copy name") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.name, forType: .string)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 560, height: 520)
    }

    private struct Item: Identifiable {
        var name: String
        var detail: String
        var id: String { name }
    }

    private var filtered: [Item] {
        let all: [Item]
        switch kind {
        case "tags":
            all = session.tags.map { Item(name: $0.name, detail: String($0.hash.prefix(7))) }
        case "remotes":
            all = session.remoteBranches.map { Item(name: $0.name, detail: String($0.hash.prefix(7))) }
        default:
            all = session.localBranches.map { Item(name: $0.name, detail: String($0.hash.prefix(7))) }
        }
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
