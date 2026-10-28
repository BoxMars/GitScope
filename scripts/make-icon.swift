import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Background rounded square with gradient.
let inset: CGFloat = 48
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.23, green: 0.42, blue: 1.0, alpha: 1),
    NSColor(srgbRed: 0.48, green: 0.24, blue: 0.92, alpha: 1)
])!
gradient.draw(in: bg, angle: -68)

// Subtle top highlight.
NSColor.white.withAlphaComponent(0.10).setFill()
NSBezierPath(roundedRect: NSRect(x: inset + 18, y: size * 0.55, width: size - (inset + 18) * 2, height: size * 0.34),
             xRadius: 150, yRadius: 150).fill()

func node(_ p: NSPoint, radius: CGFloat = 44, filled: Bool = true) {
    let r = NSRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
    let path = NSBezierPath(ovalIn: r)
    if filled {
        NSColor.white.setFill()
        path.fill()
    } else {
        NSColor.white.setStroke()
        path.lineWidth = 26
        path.stroke()
    }
}

func line(_ a: NSPoint, _ b: NSPoint) {
    let path = NSBezierPath()
    path.move(to: a)
    path.line(to: b)
    path.lineWidth = 30
    path.lineCapStyle = .round
    NSColor.white.setStroke()
    path.stroke()
}

func curve(_ a: NSPoint, _ c1: NSPoint, _ c2: NSPoint, _ b: NSPoint) {
    let path = NSBezierPath()
    path.move(to: a)
    path.curve(to: b, controlPoint1: c1, controlPoint2: c2)
    path.lineWidth = 30
    path.lineCapStyle = .round
    NSColor.white.setStroke()
    path.stroke()
}

let trunkX: CGFloat = 360
let bottom: CGFloat = 190
let top: CGFloat = 830
let midY: CGFloat = 520

line(NSPoint(x: trunkX, y: bottom), NSPoint(x: trunkX, y: top))

// Branch to the right.
curve(NSPoint(x: trunkX, y: midY),
      NSPoint(x: trunkX + 120, y: midY),
      NSPoint(x: 664, y: midY + 90),
      NSPoint(x: 664, y: midY + 170))
line(NSPoint(x: 664, y: midY + 170), NSPoint(x: 664, y: 760))

node(NSPoint(x: trunkX, y: 760))
node(NSPoint(x: trunkX, y: midY))
node(NSPoint(x: trunkX, y: 250))
node(NSPoint(x: 664, y: 760))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("icon render failed")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
