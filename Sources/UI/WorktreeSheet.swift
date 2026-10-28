import SwiftUI
import AppKit

struct NewWorktreeSheet: View {
    @ObservedObject var session: RepoSession
    @Environment(\.dismiss) private var dismiss

    @State private var path = ""
    @State private var useExistingBranch = true
    @State private var branch = ""
    @State private var newBranch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New worktree").font(.system(size: 15, weight: .semibold))
            Text("Check out a branch into a separate directory, sharing the same repository.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Location").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    TextField("Path", text: $path)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Button("Choose…") { choose() }
                }
            }

            Picker("", selection: $useExistingBranch) {
                Text("Existing branch").tag(true)
                Text("New branch").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if useExistingBranch {
                Picker("Branch", selection: $branch) {
                    ForEach(session.localBranches) { b in
                        Text(b.name).tag(b.name)
                    }
                }
                .labelsHidden()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New branch name").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("branch-name", text: $newBranch)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") {
                    let createBranch: String? = useExistingBranch ? nil : newBranch.trimmingCharacters(in: .whitespaces)
                    Task {
                        await session.addWorktree(path: path,
                                                  branch: useExistingBranch ? branch : (session.status.branch ?? "HEAD"),
                                                  createBranch: createBranch)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty
                          || (useExistingBranch && branch.isEmpty)
                          || (!useExistingBranch && newBranch.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(18)
        .frame(width: 480)
        .onAppear {
            let parent = ((session.root as NSString).deletingLastPathComponent as NSString).lastPathComponent
            let name = (session.root as NSString).lastPathComponent
            path = ((session.root as NSString).deletingLastPathComponent as NSString).appendingPathComponent("\(name)-\(parent)")
            branch = session.localBranches.first(where: { !$0.isCurrent })?.name ?? session.status.branch ?? ""
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}
