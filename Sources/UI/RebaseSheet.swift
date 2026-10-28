import SwiftUI
import AppKit

struct InteractiveRebaseSheet: View {
    @ObservedObject var session: RepoSession
    @Environment(\.dismiss) private var dismiss

    @State private var steps: [RepoSession.RebaseStep] = []
    @State private var base = ""
    @State private var count = 10
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                Text("Interactive rebase").font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("Commits", selection: $count) {
                    Text("5").tag(5)
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                }
                .labelsHidden()
                .frame(width: 70)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Theme.toolbarBackground)

            Divider().overlay(Theme.border)

            if steps.contains(where: { $0.subject.hasPrefix("Merge ") }) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: 0xD97706))
                    Text("This range contains merge commits. A plain rebase flattens them; use care.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Color(hex: 0xD97706).opacity(0.08))
            }

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if steps.isEmpty {
                EmptyHint(icon: "clock", title: "No commits to rebase", subtitle: nil)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            row(index: index, step: step)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider().overlay(Theme.border)

            HStack {
                if let errorText {
                    Text(errorText).font(.system(size: 10)).foregroundStyle(Color(hex: 0xDC2626)).lineLimit(2)
                }
                Spacer()
                Text("Oldest first · squash joins into the commit above")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button("Start rebase") {
                    Task {
                        await session.runInteractiveRebase(base: base, steps: steps)
                        if session.errorMessage == nil { dismiss() }
                    }
                }
                .disabled(steps.isEmpty || !steps.contains(where: { $0.action != "drop" }))
                .keyboardShortcut(.defaultAction)
            }
            .padding(10)
            .background(Theme.toolbarBackground)
        }
        .frame(width: 760, height: 560)
        .task { await load() }
        .onChange(of: count) { _, _ in
            Task { await load() }
        }
    }

    private func row(index: Int, step: RepoSession.RebaseStep) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing)

            Text(String(step.hash.prefix(7)))
                .font(Theme.monoSmall)
                .foregroundStyle(Color.accentColor)
                .frame(width: 58, alignment: .leading)

            Text(step.subject)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: Binding(
                get: { steps[index].action },
                set: { steps[index].action = $0 }
            )) {
                Text("pick").tag("pick")
                Text("squash").tag("squash")
                Text("drop").tag("drop")
            }
            .labelsHidden()
            .frame(width: 90)

            VStack(spacing: 1) {
                Button { move(index, by: -1) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 8, weight: .semibold))
                        .frame(width: 14, height: 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .help("Move up")
                Button { move(index, by: 1) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                        .frame(width: 14, height: 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(index == steps.count - 1)
                .help("Move down")
            }
            .foregroundStyle(.secondary)
            .frame(width: 18)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.02) : Color.clear)
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            steps.swapAt(index, target)
        }
    }

    private func load() async {
        isLoading = true
        let result = await session.loadRebaseSteps(count: count)
        base = result.base
        steps = result.steps
        if steps.isEmpty { errorText = "Not enough commits" }
        isLoading = false
    }
}
