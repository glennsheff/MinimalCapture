import AppKit
import ScreenCaptureKit

/// Module 3 (engine): one-shot captures through ScreenCaptureKit.
enum CaptureEngine {
    struct Capture {
        let image: CGImage
        /// Pixels per point, so the image pastes at its on-screen size.
        let scale: CGFloat
    }

    enum Failure: Error {
        case displayNotFound
    }

    /// Captures `screen`, or just `localRect` of it.
    /// - Parameter localRect: area in the screen's own space, in points with AppKit's
    ///   bottom-left origin (exactly what the selection overlay reports). Nil = whole screen.
    static func capture(screen: NSScreen, localRect: NSRect?) async throws -> Capture {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            throw Failure.displayNotFound
        }
        let scale = screen.backingScaleFactor
        let screenSize = screen.frame.size

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Failure.displayNotFound
        }

        // Leave this app's own windows (overlay, history panel) out of the picture.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApp = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.captureResolution = .best

        var sizeInPoints = screenSize
        if let localRect {
            // AppKit measures y from the bottom of the screen; ScreenCaptureKit from the top.
            config.sourceRect = CGRect(
                x: localRect.minX,
                y: screenSize.height - localRect.maxY,
                width: localRect.width,
                height: localRect.height
            )
            sizeInPoints = localRect.size
        }
        config.width = max(1, Int((sizeInPoints.width * scale).rounded()))
        config.height = max(1, Int((sizeInPoints.height * scale).rounded()))

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(image: image, scale: scale)
    }
}
