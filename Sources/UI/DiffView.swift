import SwiftUI
import AppKit

struct FileDiffView: View {
    var diff: FileDiff?
    var file: FileChange?
    var isLoading: Bool
    var mode: AppModel.DiffMode
    var imagePair: RepoSession.ImagePair? = nil
    var stagedContext: Bool? = nil          // nil = commit diff, true/false = index/worktree
    var onStageHunk: ((DiffHunk) -> Void)? = nil
    var onUnstageHunk: ((DiffHunk) -> Void)? = nil
    var onStageFile: (() -> Void)? = nil
    var onUnstageFile: (() -> Void)? = nil
    var onDiscardFile: (() -> Void)? = nil

    private var language: String {
        SyntaxHighlighter.family(for: file?.path ?? diff?.path ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.subtleBorder)
            content
        }
        .background(Theme.editorBackground)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let file {
                StatusGlyph(kind: file.kind)
                Text(file.path)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let old = file.oldPath, old != file.path {
                    Text("← \(old)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(diff?.path ?? "Diff")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            }

            Spacer(minLength: 6)

            if let diff, !diff.hunks.isEmpty {
                Text("+\(diff.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count })")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x16A34A))
                Text("-\(diff.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count })")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xDC2626))
            }

            if file != nil, let onStageFile, stagedContext == false {
                Button("Stage") { onStageFile() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
            }
            if file != nil, let onUnstageFile, stagedContext == true {
                Button("Unstage") { onUnstageFile() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
            }
            if file != nil, let onDiscardFile, stagedContext == false {
                Button("Discard") { onDiscardFile() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: 0xDC2626))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.toolbarBackground)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let imagePair, imagePair.path == (file?.path ?? diff?.path ?? imagePair.path) {
            ImageDiffView(pair: imagePair)
        } else if let diff {
            if diff.isBinary {
                EmptyHint(icon: "doc.zipper", title: "Binary file", subtitle: "Diff preview is not available.")
            } else if diff.hunks.isEmpty {
                EmptyHint(icon: "equal.circle", title: "No textual changes",
                          subtitle: file?.kind == .typeChanged ? "Only the file mode changed." : nil)
            } else {
                DiffBody(diff: diff, language: language, mode: mode,
                         onStageHunk: onStageHunk, onUnstageHunk: onUnstageHunk)
            }
        } else if file != nil {
            EmptyHint(icon: "doc.text.magnifyingglass", title: "Select a file", subtitle: nil)
        } else {
            EmptyHint(icon: "rectangle.split.2x1", title: "No file selected",
                      subtitle: "Choose a changed file to inspect its diff.")
        }
    }
}

private struct DiffBody: View {
    var diff: FileDiff
    var language: String
    var mode: AppModel.DiffMode
    var onStageHunk: ((DiffHunk) -> Void)?
    var onUnstageHunk: ((DiffHunk) -> Void)?

    private var totalLines: Int {
        diff.hunks.reduce(0) { $0 + $1.lines.count + 1 }
    }

    private let maxLines = 6000

    private enum Item: Identifiable {
        case header(String, DiffHunk)
        case line(DiffLine)
        case side(SideBySideRow)

        var id: String {
            switch self {
            case .header(let text, _): return "h-\(text)"
            case .line(let line): return "l-\(line.id)-\(line.text.hashValue)"
            case .side(let row): return "s-\(row.id)"
            }
        }
    }

    private var items: [Item] {
        var result: [Item] = []
        if mode == .unified {
            for hunk in diff.hunks {
                result.append(.header(hunk.header, hunk))
                for line in hunk.lines { result.append(.line(line)) }
            }
        } else {
            let rows = DiffParser.sideBySide(diff)
            for row in rows {
                if row.kind == .hunkHeader, let header = row.header {
                    result.append(.header(header, DiffHunk(header: header, oldStart: 0, oldCount: 0,
                                                           newStart: 0, newCount: 0, lines: [])))
                } else {
                    result.append(.side(row))
                }
            }
        }
        return result
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .header(let text, let hunk):
                        hunkHeader(text: text, hunk: hunk)
                    case .line(let line):
                        UnifiedLineRow(line: line, language: language)
                    case .side(let row):
                        SideBySideRowView(row: row, language: language)
                    }
                }
                if totalLines > maxLines {
                    Text("Diff truncated — \(totalLines) lines")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
            .padding(.vertical, 2)
        }
        .background(Theme.editorBackground)
    }

    @ViewBuilder
    private func hunkHeader(text: String, hunk: DiffHunk) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.adaptive(light: 0x1E40AF, dark: 0x93C5FD))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let onStageHunk {
                Button("Stage hunk") { onStageHunk(hunk) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
            }
            if let onUnstageHunk {
                Button("Unstage hunk") { onUnstageHunk(hunk) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.hunkBackground)
    }
}

private struct UnifiedLineRow: View {
    var line: DiffLine
    var language: String

    private var background: Color {
        switch line.kind {
        case .added: return Theme.diffAddedBackground
        case .removed: return Theme.diffRemovedBackground
        default: return .clear
        }
    }

    private var gutterBackground: Color {
        switch line.kind {
        case .added: return Theme.diffAddedGutter
        case .removed: return Theme.diffRemovedGutter
        default: return .clear
        }
    }

    private var marker: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "-"
        default: return " "
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .added: return Color(hex: 0x16A34A)
        case .removed: return Color(hex: 0xDC2626)
        default: return .clear
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldNumber.map(String.init) ?? "")
                .frame(width: 42, alignment: .trailing)
                .padding(.trailing, 6)
                .background(gutterBackground)
            Text(line.newNumber.map(String.init) ?? "")
                .frame(width: 42, alignment: .trailing)
                .padding(.trailing, 6)
                .background(gutterBackground)
            Text(marker)
                .frame(width: 14)
                .foregroundStyle(markerColor)
            Text(SyntaxColors.attributed(line.text.isEmpty ? " " : line.text, family: language))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(Theme.adaptive(light: 0x6B6B72, dark: 0x8A8A90))
        .frame(height: 19)
        .background(background)
    }
}

private struct SideBySideRowView: View {
    var row: SideBySideRow
    var language: String

    var body: some View {
        HStack(spacing: 0) {
            cell(number: row.leftNumber, text: row.leftText, side: .left)
            Rectangle().fill(Theme.subtleBorder).frame(width: 0.5)
            cell(number: row.rightNumber, text: row.rightText, side: .right)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 19)
    }

    private enum Side { case left, right }

    @ViewBuilder
    private func cell(number: Int?, text: String?, side: Side) -> some View {
        let background: Color = {
            switch (row.kind, side) {
            case (.removed, .left), (.replaced, .left): return Theme.diffRemovedBackground
            case (.added, .right), (.replaced, .right): return Theme.diffAddedBackground
            default: return .clear
            }
        }()
        HStack(spacing: 0) {
            Text(number.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 5)
                .foregroundStyle(.tertiary)
            Text(text.map { SyntaxColors.attributed($0.isEmpty ? " " : $0, family: language) } ?? AttributedString(""))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .frame(maxWidth: .infinity)
        .clipped()
        .background(background)
    }
}
