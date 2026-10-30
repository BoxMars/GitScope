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

    // Body: Big Sur-style squircle
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Base gradient
    let gradient = CGGradient(colorsSpace: space,
                              colors: [color(0x66B6FF), color(0x1E40AF)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 512, y: 924),
                           end: CGPoint(x: 512, y: 100),
                           options: [])

    // Soft glow from the top-left
    let glow = CGGradient(colorsSpace: space,
                          colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: 400, y: 800), startRadius: 0,
                           endCenter: CGPoint(x: 400, y: 800), endRadius: 620,
                           options: [])

    // Inner rim
    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xFFFFFF, 0.16))
    ctx.setLineWidth(3)
    ctx.strokePath()

    ctx.restoreGState()

    // Reticle: four arcs + ticks
    let center = CGPoint(x: 512, y: 512)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0xFFFFFF, 0.22))
    ctx.setLineWidth(9)
    for start in stride(from: 22.0, to: 360.0, by: 90.0) {
        ctx.addArc(center: center, radius: 252,
                   startAngle: CGFloat(start) * .pi / 180,
                   endAngle: CGFloat(start + 46) * .pi / 180,
                   clockwise: false)
        ctx.strokePath()
    }
    ctx.setLineWidth(8)
    for angle in stride(from: 0.0, to: 360.0, by: 90.0) {
        let a = CGFloat(angle) * .pi / 180
        let r0: CGFloat = 226, r1: CGFloat = 282
        ctx.move(to: CGPoint(x: center.x + cos(a) * r0, y: center.y + sin(a) * r0))
        ctx.addLine(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
        ctx.strokePath()
    }

    // Commit graph (top-based y helper)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: 1024 - y) }
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(color(0xFFFFFF, 0.96))
    ctx.setLineWidth(17)

    ctx.move(to: p(404, 344))
    ctx.addLine(to: p(404, 470))
    ctx.strokePath()
    ctx.move(to: p(404, 530))
    ctx.addLine(to: p(404, 664))
    ctx.strokePath()

    ctx.move(to: p(434, 500))
    ctx.addCurve(to: p(630, 640),
                 control1: p(528, 500),
                 control2: p(630, 556))
    ctx.strokePath()

    // Nodes
    for y in [344.0, 664.0] {
        let r: CGFloat = 29
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: 404 - r, y: 1024 - y - r, width: r * 2, height: r * 2))
    }
    do {
        let r: CGFloat = 29
        ctx.fillEllipse(in: CGRect(x: 630 - r, y: 1024 - 640 - r, width: r * 2, height: r * 2))
    }
    // Merge node: open ring, gradient shows through
    do {
        let r: CGFloat = 30
        let c = p(404, 500)
        ctx.setStrokeColor(color(0xFFFFFF))
        ctx.setLineWidth(15)
        ctx.strokeEllipse(in: CGRect(x: c.x - r + 7.5, y: c.y - r + 7.5, width: (r - 7.5) * 2, height: (r - 7.5) * 2))
    }

    // Write PNG
    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

render(to: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon.png")
