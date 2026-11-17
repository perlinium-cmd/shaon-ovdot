import AppKit

// Draws the app icon at any pixel size (vector, so every size is crisp).
func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let cs = CGColorSpaceCreateDeviceRGB()
    func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a])!
    }
    // macOS icon grid: 824/1024 body, centered
    let body = s * 824 / 1024, inset = (s - body) / 2
    let rect = CGRect(x: inset, y: inset, width: body, height: body)
    let path = CGPath(roundedRect: rect, cornerWidth: body * 0.225, cornerHeight: body * 0.225, transform: nil)

    // drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: col(0x000000, 0.35))
    ctx.addPath(path); ctx.setFillColor(col(0x0F766E)); ctx.fillPath()
    ctx.restoreGState()

    // body gradient
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [col(0x2DD4BF), col(0x0F9488), col(0x0B5F59)] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: s / 2, y: rect.maxY), end: CGPoint(x: s / 2, y: rect.minY), options: [])
    // soft glass highlight on the top half
    let hl = CGGradient(colorsSpace: cs, colors: [col(0xFFFFFF, 0.28), col(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: s / 2, y: rect.maxY), end: CGPoint(x: s / 2, y: rect.midY), options: [])
    ctx.restoreGState()

    // inner rim
    ctx.saveGState()
    ctx.addPath(path); ctx.setStrokeColor(col(0xFFFFFF, 0.25)); ctx.setLineWidth(max(1, s * 0.004)); ctx.strokePath()
    ctx.restoreGState()

    // clock
    let c = CGPoint(x: s / 2, y: s / 2)
    let R = body * 0.34
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02, color: col(0x04322F, 0.45))
    ctx.setStrokeColor(col(0xFFFFFF)); ctx.setLineWidth(body * 0.05)
    ctx.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)); ctx.strokePath()
    ctx.restoreGState()

    // hour ticks — nod to the wheel picker's teeth
    ctx.setLineCap(.round)
    for i in 0..<12 {
        let a = CGFloat(i) * .pi / 6
        let major = i % 3 == 0
        let r1 = R * 0.80, r2 = R * (major ? 0.62 : 0.70)
        ctx.setStrokeColor(col(0xFFFFFF, major ? 0.95 : 0.6))
        ctx.setLineWidth(body * (major ? 0.028 : 0.018))
        ctx.move(to: CGPoint(x: c.x + sin(a) * r1, y: c.y + cos(a) * r1))
        ctx.addLine(to: CGPoint(x: c.x + sin(a) * r2, y: c.y + cos(a) * r2))
        ctx.strokePath()
    }
    // hands (10:10 reads friendly)
    func hand(_ angle: CGFloat, _ len: CGFloat, _ w: CGFloat) {
        ctx.setStrokeColor(col(0xFFFFFF)); ctx.setLineWidth(w)
        ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x + sin(angle) * len, y: c.y + cos(angle) * len)); ctx.strokePath()
    }
    hand(-.pi / 3, R * 0.46, body * 0.045)        // hour hand
    hand(.pi / 3, R * 0.68, body * 0.034)         // minute hand
    ctx.setFillColor(col(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: c.x - body * 0.03, y: c.y - body * 0.03, width: body * 0.06, height: body * 0.06))
    ctx.setFillColor(col(0x0F766E))
    ctx.fillEllipse(in: CGRect(x: c.x - body * 0.013, y: c.y - body * 0.013, width: body * 0.026, height: body * 0.026))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
let sizes: [(name: String, px: Int, size: String, scale: String)] = [
    ("16", 16, "16x16", "1x"), ("16@2x", 32, "16x16", "2x"), ("32", 32, "32x32", "1x"), ("32@2x", 64, "32x32", "2x"),
    ("128", 128, "128x128", "1x"), ("128@2x", 256, "128x128", "2x"), ("256", 256, "256x256", "1x"), ("256@2x", 512, "256x256", "2x"),
    ("512", 512, "512x512", "1x"), ("512@2x", 1024, "512x512", "2x"),
]
var images: [String] = []
for e in sizes {
    try! draw(e.px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(e.name).png"))
    images.append("{\"filename\":\"icon_\(e.name).png\",\"idiom\":\"mac\",\"scale\":\"\(e.scale)\",\"size\":\"\(e.size)\"}")
}
try! "{\"images\":[\(images.joined(separator: ","))],\"info\":{\"author\":\"xcode\",\"version\":1}}".write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
try! draw(1024).write(to: URL(fileURLWithPath: "\(dir)/../../../tools/icon-preview.png"))
