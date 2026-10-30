import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func render(to path: String) {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Deep navy, diagonal
    let base = CGGradient(colorsSpace: space,
                          colors: [color(0x1B2A4D), color(0x080C18)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(base,
                           start: CGPoint(x: 180, y: 900),
                           end: CGPoint(x: 880, y: 120),
                           options: [])

    // Electric-blue glow behind the mark
    let glow = CGGradient(colorsSpace: space,
                          colors: [color(0x3B82F6, 0.38), color(0x3B82F6, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: 512, y: 600), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 600), endRadius: 520,
                           options: [])

    // Cool highlight at the top
    let top = CGGradient(colorsSpace: space,
                         colors: [color(0x818CF8, 0.16), color(0x818CF8, 0)] as CFArray,
                         locations: [0, 1])!
    ctx.drawRadialGradient(top,
                           startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 900), endRadius: 420,
                           options: [])

    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xFFFFFF, 0.10))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // Glyph: symmetric merge, centered on x = 512
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: 1024 - y) }
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(color(0xF8FAFF))
    ctx.setLineWidth(34)

    // Left and right branches curving into the merge node
    ctx.move(to: p(372, 368))
    ctx.addCurve(to: p(500, 546),
                 control1: p(372, 470),
                 control2: p(430, 546))
    ctx.strokePath()

    ctx.move(to: p(652, 368))
    ctx.addCurve(to: p(524, 546),
                 control1: p(652, 470),
                 control2: p(594, 546))
    ctx.strokePath()

    // Trunk below the merge node
    ctx.move(to: p(512, 586))
    ctx.addLine(to: p(512, 704))
    ctx.strokePath()

    // Nodes
    for (x, y, r) in [(372.0, 340.0, 28.0), (652.0, 340.0, 28.0)] {
        ctx.setFillColor(color(0xF8FAFF))
        ctx.fillEllipse(in: CGRect(x: x - r, y: 1024 - y - r, width: r * 2, height: r * 2))
    }
    let mr: CGFloat = 36
    ctx.setFillColor(color(0xF8FAFF))
    ctx.fillEllipse(in: CGRect(x: 512 - mr, y: 1024 - 560 - mr, width: mr * 2, height: mr * 2))

    // Subtle shadow under the nodes is faked with a soft dark ring
    ctx.setStrokeColor(color(0x000000, 0.22))
    ctx.setLineWidth(2)
    ctx.strokeEllipse(in: CGRect(x: 512 - mr, y: 1024 - 560 - mr, width: mr * 2, height: mr * 2))

    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

render(to: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon.png")
