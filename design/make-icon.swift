// Draws the Chordy app icon: coral "vocal cord" bars on a dark rounded square.
// swift design/make-icon.swift <out-dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = s / 1024

    // macOS icon grid: 824pt body centred in 1024, corner ~185, soft drop shadow.
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = CGPath(roundedRect: body, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 28 * k, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.20, green: 0.15, blue: 0.16, alpha: 1).cgColor,
        NSColor(red: 0.07, green: 0.06, blue: 0.07, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Warm glow behind the bars.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 1, green: 0.45, blue: 0.38, alpha: 0.38).cgColor,
        NSColor(red: 1, green: 0.45, blue: 0.38, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512 * k, y: 512 * k), startRadius: 0,
                           endCenter: CGPoint(x: 512 * k, y: 512 * k), endRadius: 400 * k, options: [])

    // Bars mirrored around the centre with a bell envelope, like the dictation pill.
    let heights: [CGFloat] = [0.16, 0.30, 0.52, 0.80, 1.0, 0.80, 0.52, 0.30, 0.16]
    let barW: CGFloat = 50 * k, gap: CGFloat = 30 * k, maxH: CGFloat = 470 * k
    let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    let bars = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 1.0, green: 0.62, blue: 0.48, alpha: 1).cgColor,
        NSColor(red: 1.0, green: 0.40, blue: 0.36, alpha: 1).cgColor,
        NSColor(red: 0.93, green: 0.30, blue: 0.42, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 0.5, 1])!
    for (i, h) in heights.enumerated() {
        let height = max(barW, maxH * h)
        let rect = CGRect(x: 512 * k - total / 2 + CGFloat(i) * (barW + gap), y: 512 * k - height / 2, width: barW, height: height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(bars, start: CGPoint(x: 0, y: 512 * k + maxH / 2), end: CGPoint(x: 0, y: 512 * k - maxH / 2), options: [])
        ctx.restoreGState()
    }
    // Subtle top highlight and edge.
    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    ctx.setLineWidth(3 * k)
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! render(size * scale).write(to: out.appending(path: name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: out.appending(path: "Contents.json"))
try! render(1024).write(to: out.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "design/icon-1024.png"))
