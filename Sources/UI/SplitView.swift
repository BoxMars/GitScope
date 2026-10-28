import SwiftUI
import AppKit

/// Two panes on the canvas with a 10pt gap that doubles as a drag handle.
struct CanvasSplitView<Left: View, Right: View>: View {
    var initialWidth: CGFloat = 470
    var minLeft: CGFloat = 340
    var minRight: CGFloat = 380
    var gap: CGFloat = 9
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    @State private var leftWidth: CGFloat = 470
    @State private var dragging = false
    @State private var hovering = false
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let total = proxy.size.width
            let maxLeft = max(minLeft, total - minRight - gap)
            let clamped = min(max(leftWidth, minLeft), maxLeft)
            HStack(spacing: 0) {
                left()
                    .frame(width: clamped)
                handle(total: total, maxLeft: maxLeft)
                right()
                    .frame(maxWidth: .infinity)
            }
            .onAppear {
                leftWidth = min(max(initialWidth, minLeft), maxLeft)
            }
        }
    }

    private func handle(total: CGFloat, maxLeft: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: gap)
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .fill(hovering || dragging ? Theme.accent.opacity(0.7) : Theme.border)
                    .frame(width: hovering || dragging ? 2 : 1)
            }
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = leftWidth
                            dragging = true
                        }
                        let start = dragStartWidth ?? leftWidth
                        leftWidth = min(max(start + value.translation.width, minLeft), maxLeft)
                    }
                    .onEnded { _ in
                        dragging = false
                        dragStartWidth = nil
                    }
            )
    }
}
