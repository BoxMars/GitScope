import SwiftUI

enum SyntaxTokenKind {
    case plain
    case keyword
    case string
    case comment
    case number
    case typeName
    case function
}

struct SyntaxSegment {
    var text: String
    var kind: SyntaxTokenKind
}

enum SyntaxHighlighter {
    static let keywordSets: [String: Set<String>] = [
        "swift": ["func", "let", "var", "if", "else", "guard", "return", "class", "struct", "enum", "protocol", "extension", "import", "for", "while", "switch", "case", "default", "break", "continue", "init", "self", "super", "nil", "true", "false", "try", "catch", "throw", "throws", "async", "await", "public", "private", "internal", "fileprivate", "static", "final", "override", "where", "in", "as", "is", "some", "any", "defer", "do", "repeat", "inout", "typealias", "associatedtype", "mutating", "nonmutating", "lazy", "weak", "unowned", "optional", "required", "convenience", "subscript", "operator", "precedencegroup"],
        "js": ["function", "const", "let", "var", "if", "else", "for", "while", "return", "class", "extends", "new", "this", "import", "export", "from", "default", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "null", "undefined", "true", "false", "switch", "case", "break", "continue", "of", "in", "yield", "static", "get", "set", "interface", "type", "enum", "implements", "public", "private", "protected", "readonly", "as", "declare", "namespace"],
        "python": ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "raise", "with", "lambda", "yield", "global", "nonlocal", "pass", "break", "continue", "assert", "del", "in", "is", "not", "and", "or", "None", "True", "False", "async", "await", "self"],
        "rust": ["fn", "let", "mut", "struct", "enum", "impl", "trait", "pub", "use", "mod", "match", "if", "else", "for", "while", "loop", "return", "self", "Self", "super", "crate", "const", "static", "async", "await", "move", "ref", "where", "as", "in", "unsafe", "dyn", "type", "true", "false", "Some", "None", "Ok", "Err"],
        "go": ["func", "package", "import", "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer", "select", "case", "default", "if", "else", "for", "range", "return", "switch", "break", "continue", "fallthrough", "nil", "true", "false", "make", "new", "len", "cap", "append", "error", "string", "int", "bool", "byte", "rune", "float64"],
        "c": ["int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "struct", "union", "enum", "typedef", "static", "const", "extern", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "goto", "sizeof", "include", "define", "ifdef", "ifndef", "endif", "class", "public", "private", "protected", "new", "delete", "namespace", "using", "template", "virtual", "override", "nullptr", "true", "false", "auto", "fn"],
        "ruby": ["def", "class", "module", "if", "elsif", "else", "unless", "while", "until", "for", "in", "do", "end", "return", "yield", "begin", "rescue", "ensure", "raise", "require", "attr_accessor", "self", "nil", "true", "false", "and", "or", "not", "then", "case", "when"],
        "sql": ["SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "INDEX", "DROP", "ALTER", "AND", "OR", "NOT", "NULL", "AS", "DISTINCT", "COUNT", "SUM", "AVG", "MIN", "MAX"],
        "shell": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "return", "export", "local", "echo", "cd", "set", "unset", "source", "exit", "eval"],
    ]

    static func family(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx", "mjs", "cjs", "vue", "svelte": return "js"
        case "py", "pyi": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt", "kts", "cs", "scala", "dart": return "c"
        case "rb", "rake", "gemspec": return "ruby"
        case "sql": return "sql"
        case "sh", "bash", "zsh", "fish", "ps1": return "shell"
        default: return "plain"
        }
    }

    static func highlight(_ line: String, family: String) -> [SyntaxSegment] {
        guard family != "plain", !line.isEmpty else {
            return [SyntaxSegment(text: line, kind: .plain)]
        }
        let keywords = keywordSets[family] ?? []
        var segments: [SyntaxSegment] = []
        var plain = ""
        var index = line.startIndex

        func flushPlain() {
            if !plain.isEmpty {
                segments.append(SyntaxSegment(text: plain, kind: .plain))
                plain = ""
            }
        }

        while index < line.endIndex {
            let ch = line[index]

            // Comments
            if family == "python" || family == "shell" || family == "ruby", ch == "#" {
                flushPlain()
                segments.append(SyntaxSegment(text: String(line[index...]), kind: .comment))
                return segments
            }
            if family != "python" && family != "shell", ch == "/", line.index(after: index) < line.endIndex,
               line[line.index(after: index)] == "/" {
                flushPlain()
                segments.append(SyntaxSegment(text: String(line[index...]), kind: .comment))
                return segments
            }

            // Strings
            if ch == "\"" || ch == "'" || ch == "`" {
                flushPlain()
                var end = line.index(after: index)
                var escaped = false
                while end < line.endIndex {
                    let c = line[end]
                    if escaped { escaped = false }
                    else if c == "\\" { escaped = true }
                    else if c == ch { end = line.index(after: end); break }
                    end = line.index(after: end)
                }
                segments.append(SyntaxSegment(text: String(line[index..<end]), kind: .string))
                index = end
                continue
            }

            // Numbers
            if ch.isNumber {
                flushPlain()
                var end = index
                while end < line.endIndex, line[end].isNumber || line[end] == "." || line[end] == "x" || line[end].isHexDigit {
                    end = line.index(after: end)
                }
                segments.append(SyntaxSegment(text: String(line[index..<end]), kind: .number))
                index = end
                continue
            }

            // Identifiers / keywords
            if ch.isLetter || ch == "_" || ch == "@" || ch == "#" {
                flushPlain()
                var end = index
                while end < line.endIndex, line[end].isLetter || line[end].isNumber || line[end] == "_" || line[end] == "@" {
                    end = line.index(after: end)
                }
                let word = String(line[index..<end])
                var kind: SyntaxTokenKind = .plain
                if keywords.contains(word) || keywords.contains(word.uppercased()) {
                    kind = .keyword
                } else if let first = word.first, first.isUppercase {
                    kind = .typeName
                } else {
                    var lookahead = end
                    while lookahead < line.endIndex, line[lookahead] == " " { lookahead = line.index(after: lookahead) }
                    if lookahead < line.endIndex, line[lookahead] == "(" { kind = .function }
                }
                segments.append(SyntaxSegment(text: word, kind: kind))
                index = end
                continue
            }

            plain.append(ch)
            index = line.index(after: index)
        }
        flushPlain()
        return segments
    }
}

enum SyntaxColors {
    static func color(_ kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .plain: return Color.primary
        case .keyword: return Theme.adaptive(light: 0x9F1D8C, dark: 0xF472B6)
        case .string: return Theme.adaptive(light: 0x0A7F3D, dark: 0x86EFAC)
        case .comment: return Theme.adaptive(light: 0x8A8A8E, dark: 0x7C7C82)
        case .number: return Theme.adaptive(light: 0xB45309, dark: 0xFCD34D)
        case .typeName: return Theme.adaptive(light: 0x0F766E, dark: 0x5EEAD4)
        case .function: return Theme.adaptive(light: 0x1D4ED8, dark: 0x93C5FD)
        }
    }

    static func attributed(_ text: String, family: String) -> AttributedString {
        let segments = SyntaxHighlighter.highlight(text, family: family)
        var result = AttributedString()
        for segment in segments {
            var piece = AttributedString(segment.text)
            piece.foregroundColor = color(segment.kind)
            result += piece
        }
        return result
    }
}
