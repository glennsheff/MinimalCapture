import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Module 4: plain files on disk, newest 20 kept. No database.
/// Everything here is safe to call off the main thread.
nonisolated enum CaptureStore {
    static let maxItems = 20
    private static let prefix = "Capture-"

    private static let folderKey = "saveFolderPath"
    private static let keepLatestKey = "keepOnlyLatest"

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Where captures are saved: the folder chosen in the menu, or the Desktop.
    static var directory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: folderKey), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return defaultDirectory
        }
        set { UserDefaults.standard.set(newValue.path, forKey: folderKey) }
    }

    /// When on (the default), captures past the newest `maxItems` are deleted after each save.
    static var keepOnlyLatest: Bool {
        get { UserDefaults.standard.object(forKey: keepLatestKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keepLatestKey) }
    }

    /// Encodes the image as PNG (alpha preserved). The same bytes go to the clipboard and
    /// to disk, so the image is compressed exactly once. `scale` is recorded as DPI so the
    /// image pastes at its on-screen size.
    static func pngData(_ image: CGImage, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dpi = 72 * scale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }

    /// Writes already-encoded PNG bytes to the captures folder and trims the queue.
    @discardableResult
    static func save(_ png: Data) throws -> URL {
        let directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Capture-2026-11-19-18.39.10.png. Dots, not colons, in the time: a colon in a
        // file name is shown as "/" by Finder.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        let base = prefix + formatter.string(from: Date())

        // Two captures in the same second get -2, -3, ...
        var url = directory.appendingPathComponent("\(base).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)-\(counter).png")
            counter += 1
        }
        try png.write(to: url, options: .atomic)
        if keepOnlyLatest { prune() }
        return url
    }

    /// Captures on disk, newest first.
    static func recent() -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            // Only files this app wrote; anything else in the folder is left alone.
            .filter { $0.pathExtension.lowercased() == "png" && $0.lastPathComponent.hasPrefix(prefix) }
            .map { url -> (URL, Date) in
                let date = (try? url.resourceValues(forKeys: Set(keys)))?.creationDate ?? .distantPast
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Deletes every capture past the newest `maxItems`.
    static func prune() {
        for url in recent().dropFirst(maxItems) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Small thumbnail decoded straight from the file by ImageIO; the full bitmap is never
    /// held in memory.
    static func thumbnail(for url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
