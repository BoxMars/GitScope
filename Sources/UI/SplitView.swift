import SwiftUI
import AppKit

/// Two panes with a slim divider between them. Dragging the divider uses a
/// fixed coordinate space, so the hit target never moves under the pointer
/// (which is what made the old version jitter).
struct CanvasSplitView<Left: View, Right: View>: View {
    var initialWidth: CGFloat = 470
    var minLeft: CGFloat = 340
    var minRight: CGFloat = 380
    var gap: CGFloat = 9
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    @State private var leftWidth: CGFloat = 470
    @State private var dragOffset: CGFloat = 0
    @State private var dragging = false
    @State private var hovering = false

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }

    var body: some View {
        GeometryReader { proxy in
            let total = proxy.size.width
            let maxLeft = total - minRight - gap

            HStack(spacing: 0) {
                left()
                    .frame(width: clamp(leftWidth, minLeft, maxLeft))

                handle(maxLeft: maxLeft)

                right()
                    .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "canvasSplit")
            .onAppear {
                leftWidth = clamp(initialWidth, minLeft, maxLeft)
            }
            .onChange(of: total) { _, newTotal in
                leftWidth = clamp(leftWidth, minLeft, newTotal - minRight - gap)
            }
        }
    }

    private func handle(maxLeft: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())

            Rectangle()
                .fill(dragging || hovering ? Theme.accent.opacity(0.75) : Theme.border)
                .frame(width: dragging || hovering ? 2 : 1)
        }
        .frame(width: gap)
        .onHover { inside in
            hovering = inside
            if inside {
                NSCursor.resizeLeftRight.set()
            } else if !dragging {
                NSCursor.arrow.set()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("canvasSplit"))
                .onChanged { value in
                    if !dragging {
                        dragging = true
                        // Keep the grab offset so the divider doesn't jump.
                        dragOffset = leftWidth - value.startLocation.x
                    }
                    leftWidth = clamp(value.location.x + dragOffset, minLeft, maxLeft)
                }
                .onEnded { _ in
                    dragging = false
                    NSCursor.arrow.set()
                }
        )
    }
}
