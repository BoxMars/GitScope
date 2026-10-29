import SwiftUI

/// Plain file content viewer with line numbers and syntax highlighting.
struct CodeView: View {
    var text: String?
    var path: String?
    var isBinary: Bool
    var isLoading: Bool = false

    private var language: String {
        SyntaxHighlighter.family(for: path ?? "")
    }

    private var lines: [String] {
        guard let text else { return [] }
        return Array(text.components(separatedBy: "\n").prefix(8000))
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isBinary {
                EmptyHint(icon: "doc.zipper", title: "Binary file",
                          subtitle: "This file cannot be shown as text.")
            } else if text == nil {
                EmptyHint(icon: "doc.text", title: "Select a file",
                          subtitle: "Browse the repository at this commit.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 0) {
                                Text("\(index + 1)")
                                    .frame(width: 44, alignment: .trailing)
                                    .padding(.trailing, 8)
                                    .foregroundStyle(.tertiary)
                                Text(SyntaxColors.attributed(line.isEmpty ? " " : line, family: language))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.trailing, 8)
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(minHeight: 19, alignment: .top)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Theme.editorBackground)
            }
        }
    }
}
