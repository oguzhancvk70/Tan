import Foundation

enum ImageFiles {
    static let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "bmp", "gif"]
    static func isImage(_ u: URL) -> Bool { exts.contains(u.pathExtension.lowercased()) }
}

// yerel klasör
enum LocalFolderSource {
    static func images(in folder: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return e.compactMap { $0 as? URL }.filter(ImageFiles.isImage).sorted { $0.path < $1.path }
    }
}

// macOS duvar kâğıtları
enum SystemWallpaperSource {
    static let folders = ["/System/Library/Desktop Pictures", "/Library/Desktop Pictures"].map { URL(fileURLWithPath: $0) }
    static func all() -> [URL] { folders.flatMap(LocalFolderSource.images(in:)) }
}
