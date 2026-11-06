import AppKit

// çıktı klasörü
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = g.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!

    // gövde + gölge
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()

    // gökyüzü
    let sky = CGGradient(colorsSpace: cs, colors: [rgb(0x0D1238), rgb(0x34297A), rgb(0xC2507A), rgb(0xFF9A5E)] as CFArray,
                         locations: [0, 0.45, 0.75, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 330), options: [.drawsAfterEndLocation])

    // yıldızlar
    for (x, y, r) in [(250.0, 820.0, 7.0), (360, 760, 4), (300, 680, 5), (470, 850, 4), (560, 720, 3), (200, 600, 3), (820, 600, 4)] {
        ctx.setFillColor(rgb(0xFFFFFF, 0.85))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // hilal
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(rgb(0xF4F1FF))
    ctx.fillEllipse(in: CGRect(x: 640, y: 680, width: 170, height: 170))
    ctx.setBlendMode(.destinationOut)
    ctx.fillEllipse(in: CGRect(x: 690, y: 715, width: 150, height: 150))
    ctx.endTransparencyLayer()
    ctx.setBlendMode(.normal)

    // doğan güneş
    let horizon: CGFloat = 340
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: horizon, width: 1024, height: 1024))
    ctx.setShadow(offset: .zero, blur: 60, color: rgb(0xFFC46B, 0.9))
    let sunRect = CGRect(x: 512 - 200, y: horizon - 200, width: 400, height: 400)
    ctx.addEllipse(in: sunRect); ctx.clip()
    let sun = CGGradient(colorsSpace: cs, colors: [rgb(0xFFF1A8), rgb(0xFFB547)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sun, start: CGPoint(x: 512, y: horizon + 200), end: CGPoint(x: 512, y: horizon), options: [])
    ctx.restoreGState()

    // deniz
    let sea = CGGradient(colorsSpace: cs, colors: [rgb(0x2A2160), rgb(0x0F0E2E)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: 1024, height: horizon))
    ctx.drawLinearGradient(sea, start: CGPoint(x: 512, y: horizon), end: CGPoint(x: 512, y: 100), options: [])
    for (i, w) in [300.0, 220, 150, 90].enumerated() {
        let y = horizon - 28 - CGFloat(i) * 40
        ctx.setFillColor(rgb(0xFFC46B, 0.75 - Double(i) * 0.15))
        let r = CGRect(x: 512 - w / 2, y: y, width: w, height: 12)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
    }
    ctx.restoreGState()

    ctx.restoreGState()
    g.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

// macOS AppIcon boyutları
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)\(scale == 2 ? "@2x" : "").png"
        try! render(base * scale).write(to: outDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: outDir.appendingPathComponent("Contents.json"))
print("ok")
