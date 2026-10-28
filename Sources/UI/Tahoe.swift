import SwiftUI
import AppKit

/// Window-level chrome tweaks for a modern macOS look: transparent title bar,
/// hidden title text, and a glassy backdrop behind the content cards.
struct WindowChromeConfigurator: NSViewRepresentable {
    var appearance: AppModel.Appearance = .system

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.title = "GitScope"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            Self.apply(appearance, to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        Self.apply(appearance, to: window)
    }

    private static func apply(_ appearance: AppModel.Appearance, to window: NSWindow) {
        switch appearance {
        case .system: window.appearance = nil
        case .light: window.appearance = NSAppearance(named: .aqua)
        case .dark: window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Subtle gradient + soft light pools used as the backdrop under the glass panels.
enum TahoeUI {
    /// Height reserved for the traffic lights when content runs under the title bar.
    static let titlebarInset: CGFloat = 26
    /// Glass effects can force the hosting window to become translucent; kept as a switch.
    static let glassEnabled = true
}

struct AppBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(hex: 0x101012), Color(hex: 0x18181B), Color(hex: 0x0D0D0F)]
                    : [Color(hex: 0xF3F3F5), Color(hex: 0xEAEAEE), Color(hex: 0xF6F6F8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Very soft neutral pools; no colour cast on the glass panels.
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                Circle()
                    .fill(Color.white.opacity(scheme == .dark ? 0.04 : 0.55))
                    .frame(width: w * 0.6)
                    .blur(radius: 140)
                    .offset(x: -w * 0.2, y: -h * 0.32)
                Circle()
                    .fill(Color.black.opacity(scheme == .dark ? 0.18 : 0.03))
                    .frame(width: w * 0.5)
                    .blur(radius: 160)
                    .offset(x: w * 0.3, y: h * 0.3)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Makes a background strip behave like the window title bar.
    @ViewBuilder
    func windowDragArea() -> some View {
        if #available(macOS 15.0, *) {
            self.gesture(WindowDragGesture())
        } else {
            self
        }
    }

    /// Glass panel on macOS 26, a material card on older systems.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 14, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *), TahoeUI.glassEnabled {
            self.glassEffect(interactive ? .regular.interactive() : .regular,
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                )
        }
    }

    /// Small floating control chip.
    @ViewBuilder
    func glassChip(cornerRadius: CGFloat = 7) -> some View {
        if #available(macOS 26.0, *), TahoeUI.glassEnabled {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Fade content out under the top bar instead of hard-clipping it.
    @ViewBuilder
    func softTopEdge() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
