import AppKit

/// Module 4 (clipboard).
///
/// The clipboard is always given finished PNG bytes, never an NSImage. An NSImage on the
/// pasteboard is kept alive by AppKit (it supplies other formats on demand), which pins the
/// uncompressed bitmap, about 24 MB for a Retina full screen, in this process for as long
/// as the capture stays on the clipboard. PNG bytes are copied to the pasteboard server and
/// nothing is retained here; macOS still offers TIFF to apps that ask for it.
enum Clipboard {
    @discardableResult
    static func copyPNG(_ data: Data) -> Bool {
        autoreleasepool {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setData(data, forType: .png)
        }
    }

    /// Copies a saved capture straight from disk without decoding it.
    @discardableResult
    static func copyPNG(at url: URL) -> Bool {
        autoreleasepool {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
            return copyPNG(data)
        }
    }
}
