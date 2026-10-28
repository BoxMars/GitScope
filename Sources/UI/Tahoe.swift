import SwiftUI
import AppKit

/// Window-level chrome: content runs under a hidden title bar so the traffic
/// lights can live inside the sidebar.
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

enum TahoeUI {
    /// Height reserved for the traffic lights when content runs under the title bar.
    static let titlebarInset: CGFloat = 26
    /// Glass effects can force the hosting window to become translucent; kept as a switch.
    static let glassEnabled = true
}

/// Flat neutral canvas behind the floating cards (Activity Monitor style).
struct AppBackdrop: View {
    var body: some View {
        Theme.canvas.ignoresSafeArea()
    }
}

/// A page-level card: solid surface, large radius, hairline border.
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(Theme.contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = 18) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }

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
