import Foundation

/// Parses unified diff output into structured hunks.
enum DiffParser {
    static func parse(_ text: String) -> [FileDiff] {
        var files: [FileDiff] = []
        var current: FileDiff?
        var hunk: DiffHunk?
        var oldLine = 0
        var newLine = 0
        var oldRemaining = 0
        var newRemaining = 0

        func flushHunk() {
            if let hunk, var file = current {
                file.hunks.append(hunk)
                current = file
            }
            hunk = nil
        }

        func flushFile() {
            flushHunk()
            if let file = current { files.append(file) }
            current = nil
        }

        let lines = text.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("diff --git ") {
                flushFile()
                let rest = line.dropFirst("diff --git ".count)
                let parts = splitDiffPaths(String(rest))
                current = FileDiff(path: parts.1 ?? parts.0 ?? "", oldPath: parts.0, hunks: [])
                index += 1
                continue
            }

            if line.hasPrefix("@@ ") {
                flushHunk()
                if let range = parseHunkHeader(line) {
                    hunk = DiffHunk(header: line, oldStart: range.0, oldCount: range.1,
                                    newStart: range.2, newCount: range.3, lines: [])
                    oldLine = range.0
                    newLine = range.2
                    oldRemaining = range.1
                    newRemaining = range.3
                }
                index += 1
                continue
            }

            guard current != nil else {
                index += 1
                continue
            }

            if hunk != nil {
                if oldRemaining <= 0 && newRemaining <= 0 {
                    flushHunk()
                    continue
                }
                if line.hasPrefix("\\") {
                    index += 1
                    continue
                }
                if line.hasPrefix("+") {
                    hunk!.lines.append(DiffLine(kind: .added, oldNumber: nil, newNumber: newLine, text: String(line.dropFirst())))
                    newLine += 1
                    newRemaining -= 1
                    index += 1
                    continue
                }
                if line.hasPrefix("-") {
                    hunk!.lines.append(DiffLine(kind: .removed, oldNumber: oldLine, newNumber: nil, text: String(line.dropFirst())))
                    oldLine += 1
                    oldRemaining -= 1
                    index += 1
                    continue
                }
                if line.hasPrefix(" ") || line.isEmpty {
                    let text = line.isEmpty ? "" : String(line.dropFirst())
                    hunk!.lines.append(DiffLine(kind: .context, oldNumber: oldLine, newNumber: newLine, text: text))
                    oldLine += 1
                    newLine += 1
                    oldRemaining -= 1
                    newRemaining -= 1
                    index += 1
                    continue
                }
                // Anything else ends the hunk (e.g. next file header).
                flushHunk()
                continue
            }

            // File metadata before the first hunk.
            if line.hasPrefix("rename from ") {
                current?.oldPath = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                current?.path = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                current?.isBinary = true
            } else if line.hasPrefix("--- ") {
                let p = String(line.dropFirst(4))
                if p != "/dev/null" { current?.oldPath = stripPrefix(p) }
            } else if line.hasPrefix("+++ ") {
                let p = String(line.dropFirst(4))
                if p != "/dev/null" { current?.path = stripPrefix(p) }
            } else if line.hasPrefix("index ") || line.hasPrefix("similarity index")
                        || line.hasPrefix("old mode") || line.hasPrefix("new mode")
                        || line.hasPrefix("dissimilarity index") {
                // ignore
            }
            index += 1
        }

        flushFile()
        for i in files.indices {
            if files[i].path.isEmpty, let old = files[i].oldPath { files[i].path = old }
        }
        return files
    }

    static func stripPrefix(_ path: String) -> String {
        var p = path
        if p.hasPrefix("a/") || p.hasPrefix("b/") { p = String(p.dropFirst(2)) }
        if p.hasSuffix("\t") { p = String(p.dropLast()) }
        return p
    }

    private static func splitDiffPaths(_ s: String) -> (String?, String?) {
        // diff --git a/foo b/foo  (paths with spaces are quoted by git)
        if s.hasPrefix("\"") {
            // quoted form: "a/x y" "b/x y"
            var parts: [String] = []
            var current = ""
            var inQuotes = false
            var escaped = false
            for ch in s {
                if escaped { current.append(ch); escaped = false; continue }
                if ch == "\\" { escaped = true; continue }
                if ch == "\"" { inQuotes.toggle(); continue }
                if ch == " " && !inQuotes {
                    if !current.isEmpty { parts.append(current); current = "" }
                    continue
                }
                current.append(ch)
            }
            if !current.isEmpty { parts.append(current) }
            return (parts.first.map(stripPrefix), parts.count > 1 ? stripPrefix(parts[1]) : nil)
        }
        // Unquoted: split on " b/" marker, which is how git separates the two paths.
        if let range = s.range(of: " b/") {
            let a = String(s[..<range.lowerBound])
            let b = "b/" + String(s[range.upperBound...])
            return (stripPrefix(a), stripPrefix(b))
        }
        return (nil, nil)
    }

    private static func parseHunkHeader(_ line: String) -> (Int, Int, Int, Int)? {
        // @@ -1,2 +3,4 @@
        guard let regex = try? NSRegularExpression(pattern: "@@ -(\\d+)(?:,(\\d+))? \\+(\\d+)(?:,(\\d+))? @@") else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> Int {
            let r = match.range(at: i)
            return r.location == NSNotFound ? 0 : Int(ns.substring(with: r)) ?? 0
        }
        let oldStart = group(1)
        let oldCount = match.range(at: 2).location == NSNotFound ? 1 : group(2)
        let newStart = group(3)
        let newCount = match.range(at: 4).location == NSNotFound ? 1 : group(4)
        return (oldStart, oldCount, newStart, newCount)
    }

    // MARK: - Side by side

    static func sideBySide(_ diff: FileDiff) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        var counter = 0
        for hunk in diff.hunks {
            rows.append(SideBySideRow(id: counter, kind: .hunkHeader, header: hunk.header))
            counter += 1
            var i = 0
            while i < hunk.lines.count {
                let line = hunk.lines[i]
                if line.kind == .context {
                    rows.append(SideBySideRow(id: counter, kind: .context,
                                              leftNumber: line.oldNumber, leftText: line.text,
                                              rightNumber: line.newNumber, rightText: line.text))
                    counter += 1
                    i += 1
                    continue
                }
                var removed: [DiffLine] = []
                var added: [DiffLine] = []
                while i < hunk.lines.count, hunk.lines[i].kind == .removed {
                    removed.append(hunk.lines[i]); i += 1
                }
                while i < hunk.lines.count, hunk.lines[i].kind == .added {
                    added.append(hunk.lines[i]); i += 1
                }
                let pairCount = max(removed.count, added.count)
                for k in 0..<pairCount {
                    let l = k < removed.count ? removed[k] : nil
                    let r = k < added.count ? added[k] : nil
                    let kind: SideBySideRow.Kind = (l != nil && r != nil) ? .replaced : (l != nil ? .removed : .added)
                    rows.append(SideBySideRow(id: counter, kind: kind,
                                              leftNumber: l?.oldNumber, leftText: l?.text,
                                              rightNumber: r?.newNumber, rightText: r?.text))
                    counter += 1
                }
            }
        }
        return rows
    }
}
