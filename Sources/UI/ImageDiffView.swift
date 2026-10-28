import SwiftUI
import AppKit

enum ImageFile {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "svg", "ico"]

    static func isImage(_ path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }
}

struct ImageDiffView: View {
    var pair: RepoSession.ImagePair

    var body: some View {
        HStack(spacing: 0) {
            panel(title: "Before", data: pair.old)
            Divider().overlay(Theme.border)
            panel(title: "After", data: pair.new)
        }
        .background(Theme.editorBackground)
    }

    private func panel(title: String, data: Data?) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if let data, let size = NSImage(data: data)?.size {
                    Text("\(Int(size.width))×\(Int(size.height))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Theme.toolbarBackground)

            ZStack {
                CheckerboardBackground()
                if let data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                } else {
                    Text("No image")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CheckerboardBackground: View {
    var square: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let light = Theme.adaptive(light: 0xF7F7F8, dark: 0x1F1F21)
            let dark = Theme.adaptive(light: 0xEDEDEF, dark: 0x262628)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : square
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: square, height: square)
                    context.fill(Path(rect), with: .color(dark))
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
    }
}
