// Uygulama ikonunu temanın renkleriyle çizer: koyu çerçeve, açık zemin, sarı daire.
// Kullanım: swift scripts/make-icon.swift <çıktı.iconset>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MacHealth.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.09
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    color(0x585856).setFill()
    NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225).fill()

    let inner = body.insetBy(dx: body.width * 0.07, dy: body.width * 0.07)
    color(0xDFDFD7).setFill()
    NSBezierPath(roundedRect: inner, xRadius: inner.width * 0.18, yRadius: inner.width * 0.18).fill()

    let d = inner.width * 0.52
    let circle = NSRect(x: inner.midX - d / 2, y: inner.midY - d / 2, width: d, height: d)
    color(0xF3FC49).setFill()
    NSBezierPath(ovalIn: circle).fill()

    // Dört köşeli parıltı
    let c = NSPoint(x: circle.midX, y: circle.midY)
    let r = d * 0.30, w = d * 0.075
    let star = NSBezierPath()
    star.move(to: NSPoint(x: c.x, y: c.y + r))
    star.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + w, y: c.y + w), controlPoint2: NSPoint(x: c.x + w, y: c.y + w))
    star.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + w, y: c.y - w), controlPoint2: NSPoint(x: c.x + w, y: c.y - w))
    star.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - w, y: c.y - w), controlPoint2: NSPoint(x: c.x - w, y: c.y - w))
    star.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - w, y: c.y + w), controlPoint2: NSPoint(x: c.x - w, y: c.y + w))
    color(0x1F2220).setFill()
    star.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
