import AppKit
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.02, alpha: 1)])!.draw(in: rect, angle: -90)
// ring
let c = NSPoint(x: 512, y: 512)
let ring = NSBezierPath(ovalIn: NSRect(x: c.x-330, y: c.y-330, width: 660, height: 660))
NSColor(white: 1, alpha: 0.10).setFill(); ring.fill()
NSColor(white: 1, alpha: 0.25).setStroke(); ring.lineWidth = 6; ring.stroke()
let ok = NSBezierPath(ovalIn: NSRect(x: c.x-135, y: c.y-135, width: 270, height: 270))
NSGradient(colors: [NSColor(red: 0.35, green: 0.6, blue: 1, alpha: 1), NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)])!.draw(in: ok, angle: -90)
NSColor.white.setFill()
for (dx, dy, rot) in [(0.0, 250.0, 0.0), (0.0, -250.0, 180.0), (-250.0, 0.0, 90.0), (250.0, 0.0, -90.0)] {
    let t = NSAffineTransform(); t.translateX(by: c.x+dx, yBy: c.y+dy); t.rotate(byDegrees: rot)
    let p = NSBezierPath(); p.move(to: NSPoint(x: -55, y: -25)); p.line(to: NSPoint(x: 0, y: 30)); p.line(to: NSPoint(x: 55, y: -25))
    p.lineWidth = 26; p.lineCapStyle = .round; p.lineJoinStyle = .round
    p.transform(using: t as AffineTransform); NSColor.white.setStroke(); p.stroke()
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
