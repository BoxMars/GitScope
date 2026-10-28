import SwiftUI
import AppKit

struct NewBranchSheet: View {
    @ObservedObject var session: RepoSession
    var mode: BranchSheetMode

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var startPoint = ""

    private var isRename: Bool {
        if case .rename = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isRename ? "Rename branch" : "New branch")
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("branch-name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            if !isRename {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start point").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("HEAD", text: $startPoint)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isRename ? "Rename" : "Create") {
                    Task {
                        if case .rename(let branch) = mode {
                            await session.renameBranch(branch, to: name)
                        } else {
                            await session.createBranch(name: name, startPoint: startPoint.isEmpty ? nil : startPoint)
                        }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
        .onAppear {
            switch mode {
            case .create(let start):
                startPoint = start.map { String($0.prefix(7)) } ?? ""
            case .rename(let branch):
                name = branch.name
            }
        }
    }
}

struct NewTagSheet: View {
    @ObservedObject var session: RepoSession
    var targetHash: String?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New tag").font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("v1.0.0", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Message (optional)").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Release notes", text: $message)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task {
                        await session.createTag(name: name,
                                                message: message.isEmpty ? nil : message,
                                                at: targetHash)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

struct CloneSheet: View {
    @ObservedObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var destination = (NSString(string: "~/Developer").expandingTildeInPath)
    @State private var isCloning = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clone repository").font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Repository URL").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("git@github.com:user/repo.git", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Text(destination)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseDestination() }
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0xDC2626))
                    .lineLimit(3)
            }

            HStack {
                if isCloning { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Clone") { clone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.isEmpty || isCloning)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }

    private func clone() {
        isCloning = true
        errorText = nil
        let target = destination
        let repoURL = url
        Task {
            do {
                let name = (repoURL as NSString).lastPathComponent
                    .replacingOccurrences(of: ".git", with: "")
                let path = (target as NSString).appendingPathComponent(name)
                _ = try await GitCLI.runChecked(["clone", repoURL, path], in: target)
                await app.addRepository(url: URL(fileURLWithPath: path))
                dismiss()
            } catch {
                errorText = error.localizedDescription
                isCloning = false
            }
        }
    }
}
