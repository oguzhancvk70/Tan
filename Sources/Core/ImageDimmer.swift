import AppKit
import CoreImage
import CryptoKit

// koyu mod karartma (önbellekli)
enum ImageDimmer {
    static func dimmed(_ url: URL, amount: Double) -> URL? {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let key = "\(url.path)|\(mtime)|\(Int(amount * 100))"
        let name = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let out = Storage.dimmed.appendingPathComponent(name + ".jpg")
        if FileManager.default.fileExists(atPath: out.path) { return out }

        guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
        let overlay = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: amount)).cropped(to: img.extent)
        let cs = img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        do {
            try CIContext().writeJPEGRepresentation(
                of: overlay.composited(over: img), to: out, colorSpace: cs,
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92])
        } catch { return nil }
        prune()
        return out
    }

    private static func prune(keep: Int = 20) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Storage.dimmed, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b
        }
        sorted.dropFirst(keep).forEach { try? fm.removeItem(at: $0) }
    }
}

// küçük önizleme
enum Thumbnail {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    static func make(_ url: URL, maxPixel: Int = 480) -> NSImage? {
        let key = "\(url.path)#\(maxPixel)" as NSString
        if let c = cache.object(forKey: key) { return c }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: key)
        return img
    }
}
