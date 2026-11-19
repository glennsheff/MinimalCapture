import AppKit

/// Module 3 (overlay): one dimmed, borderless window per screen for drag-selecting an area.
///
/// Lifecycle: windows exist only while a selection is in progress. On mouse-up or cancel
/// they are closed and every strong reference is dropped, so ARC frees them immediately.
///
/// `isReleasedWhenClosed` is deliberately false. Setting it to true on a window that ARC also
/// owns makes AppKit send one extra release on close, which over-releases and crashes when
/// our reference is dropped. Closing and then dropping the only reference destroys the window
/// just the same.
final class SelectionOverlay {
    struct Selection {
        /// In the screen's own coordinate space: points, bottom-left origin (AppKit).
        let rect: NSRect
        let screen: NSScreen
    }

    private var windows: [OverlayWindow] = []
    private var escapeHotKey: UInt32?
    private var completion: ((Selection?) -> Void)?

    init(completion: @escaping (Selection?) -> Void) {
        self.completion = completion
    }

    func begin() {
        BackgroundCursor.enable()
        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                // .nonactivatingPanel lets the overlay take clicks without activating this app,
                // so the frontmost app keeps its active look in the screenshot.
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.setFrame(screen.frame, display: false)

            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self, weak screen] rect in
                guard let self else { return }
                if let rect, let screen {
                    self.finish(Selection(rect: rect, screen: screen))
                } else {
                    self.finish(nil)
                }
            }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }

        // Escape cancels. A temporary Carbon hotkey works without making this app active.
        escapeHotKey = HotKeyCenter.shared.register(
            keyCode: HotKeyCenter.Key.escape,
            modifiers: HotKeyCenter.Modifier.none
        ) { [weak self] in
            self?.finish(nil)
        }

        // Show the crosshair straight away, before the pointer moves. The app under the
        // pointer may re-assert its own cursor while our windows come up, so set it again
        // on the next few turns of the run loop.
        NSCursor.crosshair.set()
        for delay in [0.0, 0.05, 0.15, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.completion != nil else { return }
                NSCursor.crosshair.set()
            }
        }
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ selection: Selection?) {
        guard let completion else { return } // already finished
        self.completion = nil

        if let escapeHotKey {
            HotKeyCenter.shared.unregister(escapeHotKey)
            self.escapeHotKey = nil
        }
        for window in windows {
            (window.contentView as? SelectionView)?.onFinish = nil
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        NSCursor.arrow.set()

        // Last statement: the owner usually drops its reference to us in here.
        completion(selection)
    }
}

// macOS only lets the frontmost app change the cursor, and this app is never frontmost.
// This window-server connection property lifts that restriction for our process. It is
// not public API (there is no public equivalent); if a future macOS drops it, the only
// effect is that the pointer stays an arrow while selecting.
@_silgen_name("_CGSDefaultConnection")
private nonisolated func _CGSDefaultConnection() -> Int32

@_silgen_name("CGSSetConnectionProperty")
private nonisolated func CGSSetConnectionProperty(_ connection: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

enum BackgroundCursor {
    private static var enabled = false

    static func enable() {
        guard !enabled else { return }
        enabled = true
        let connection = _CGSDefaultConnection()
        _ = CGSSetConnectionProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

private final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SelectionView: NSView {
    var onFinish: ((NSRect?) -> Void)?

    private var anchor: NSPoint?
    private var selection: NSRect?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(
            x: min(anchor.x, point.x),
            y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x),
            height: abs(point.y - anchor.y)
        ).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // Snap to whole pixels so the capture is not resampled.
        let rect = selection.map { backingAlignedRect($0, options: .alignAllEdgesNearest) }
        anchor = nil
        selection = nil
        // A plain click (or a sliver) counts as cancel.
        if let rect, rect.width >= 3, rect.height >= 3 {
            onFinish?(rect)
        } else {
            onFinish?(nil)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish?(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.3).setFill()
        bounds.fill()

        guard let selection, !selection.isEmpty else { return }
        // Punch a fully transparent hole for the selected area.
        NSColor.clear.set()
        selection.fill(using: .copy)

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}
