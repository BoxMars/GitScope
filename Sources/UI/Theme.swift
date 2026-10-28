import SwiftUI
import AppKit

enum Theme {
    static let sidebarWidth: CGFloat = 236
    static let historyWidth: CGFloat = 430
    static let commitRowHeight: CGFloat = 46
    static let laneWidth: CGFloat = 12
    static let rowHeight: CGFloat = 22

    static let mono = Font.system(size: 12, design: .monospaced)
    static let monoSmall = Font.system(size: 11, design: .monospaced)
    static let monoBold = Font.system(size: 12, weight: .semibold, design: .monospaced)

    static let graphColors: [Color] = [
        Color(hex: 0x3B82F6), // blue
        Color(hex: 0xA855F7), // purple
        Color(hex: 0xEC4899), // pink
        Color(hex: 0xF59E0B), // amber
        Color(hex: 0x14B8A6), // teal
        Color(hex: 0x22C55E), // green
        Color(hex: 0x6366F1), // indigo
        Color(hex: 0xEF4444), // red
        Color(hex: 0x06B6D4), // cyan
        Color(hex: 0x8B5CF6), // violet
    ]

    static func graphColor(_ index: Int) -> Color {
        graphColors[abs(index) % graphColors.count]
    }

    static let sidebarBackground = adaptive(light: 0xF3F3F5, dark: 0x1C1C1E)
    static let contentBackground = adaptive(light: 0xFFFFFF, dark: 0x1F1F22)
    static let canvas = adaptive(light: 0xEFEFF2, dark: 0x131315)
    static let editorBackground = adaptive(light: 0xFFFFFF, dark: 0x191919)
    static let toolbarBackground = adaptive(light: 0xF8F8FA, dark: 0x232325)
    static let border = adaptive(light: 0xE2E2E6, dark: 0x35353A)
    static let subtleBorder = adaptive(light: 0xECECEF, dark: 0x2C2C30)
    static let secondaryText = adaptive(light: 0x6B6B72, dark: 0x9A9AA2)

    static let diffAddedBackground = adaptive(light: 0xE7F7EC, dark: 0x12281B)
    static let diffAddedGutter = adaptive(light: 0xD3F0DC, dark: 0x17351F)
    static let diffRemovedBackground = adaptive(light: 0xFDEBEC, dark: 0x2C1518)
    static let diffRemovedGutter = adaptive(light: 0xF8D8DA, dark: 0x3A1A1E)
    static let hunkBackground = adaptive(light: 0xEFF4FC, dark: 0x1A2233)

    static let selectionBackground = adaptive(light: 0xE3EDFD, dark: 0x24354E)
    /// Sidebar row selection: filled accent, like the system apps.
    static let sidebarSelection = Color.accentColor

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Small components

struct RefBadge: View {
    var ref: RefLabel
    var compact: Bool = false

    private var tint: Color {
        switch ref.kind {
        case .head: return Color(hex: 0x16A34A)
        case .localBranch: return ref.isCurrent ? Color(hex: 0x2563EB) : Color(hex: 0x3B82F6)
        case .remoteBranch: return Color(hex: 0x7C3AED)
        case .tag: return Color(hex: 0xD97706)
        }
    }

    private var icon: String {
        switch ref.kind {
        case .head: return "arrow.triangle.branch"
        case .localBranch: return "arrow.triangle.branch"
        case .remoteBranch: return "cloud"
        case .tag: return "tag.fill"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(ref.displayName)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(tint.opacity(0.35), lineWidth: 0.6))
        .help(ref.kind == .tag ? "Tag" : "Branch")
    }
}

struct StatusGlyph: View {
    var kind: ChangeKind

    private var color: Color {
        switch kind {
        case .added, .untracked: return Color(hex: 0x16A34A)
        case .modified: return Color(hex: 0xD97706)
        case .deleted: return Color(hex: 0xDC2626)
        case .renamed, .copied: return Color(hex: 0x2563EB)
        case .unmerged: return Color(hex: 0xDB2777)
        case .typeChanged: return Color(hex: 0x7C3AED)
        }
    }

    var body: some View {
        Text(kind.symbol)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 14, height: 14)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
    }
}

struct ToolbarButton: View {
    var icon: String
    var help: String
    var isEnabled: Bool = true
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .background(hovering ? Color.primary.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}


struct Avatar: View {
    var name: String
    var size: CGFloat = 20

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private var color: Color {
        let hash = abs(name.hashValue)
        return Theme.graphColor(hash % Theme.graphColors.count)
    }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.22))
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

struct EmptyHint: View {
    var icon: String
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
