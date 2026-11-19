import AppKit
import SwiftUI

/// Module 5: transient floating panel with the last 20 captures.
///
/// The panel, its hosting controller and the SwiftUI view exist only while it is on screen.
/// Any dismissal goes through `close()`, which destroys all three.
///
/// Two deliberate differences from a stock panel:
/// - `hidesOnDeactivate` is false. This app is never the active app (the panel is
///   non-activating so you can paste straight into what you were working in), and AppKit
///   keeps hides-on-deactivate panels invisible while their app is inactive. Instead the
///   panel closes itself when it loses key status, i.e. when you click anywhere else.
/// - `isReleasedWhenClosed` is false; see the note in SelectionOverlay.
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private var panel: HistoryPanel?
    private var escapeHotKey: UInt32?
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func show() {
        let model = HistoryModel()
        let view = HistoryView(model: model) { [weak self] url in
            self?.pick(url)
        }

        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: HistoryView.size.width, height: HistoryView.size.height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.contentViewController = NSHostingController(rootView: view)
        panel.delegate = self

        // Centre on the screen the pointer is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.midY - panel.frame.height / 2
            ))
        }

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)

        escapeHotKey = HotKeyCenter.shared.register(
            keyCode: HotKeyCenter.Key.escape,
            modifiers: HotKeyCenter.Modifier.none
        ) { [weak self] in
            self?.close()
        }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil

        if let escapeHotKey {
            HotKeyCenter.shared.unregister(escapeHotKey)
            self.escapeHotKey = nil
        }
        panel.delegate = nil
        panel.contentViewController = nil // drops the hosting controller and the SwiftUI tree
        panel.close()
        onClose()
    }

    private func pick(_ url: URL) {
        if Clipboard.copyPNG(at: url) {
            NSSound(named: "Pop")?.play()
        } else {
            NSSound.beep()
        }
        close()
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

private final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@Observable
private final class HistoryModel {
    struct Item: Identifiable {
        let url: URL
        let thumbnail: CGImage
        var id: URL { url }
    }

    /// Longest edge of a thumbnail in pixels. 240 px is about 140 KB decoded per item,
    /// under 3 MB for a full grid; lower it for an even smaller footprint.
    static let thumbnailPixels = 240

    var items: [Item] = []
    var loaded = false
    var hovered: URL?

    func load() async {
        let pixels = Self.thumbnailPixels
        let loaded = await Task.detached(priority: .userInitiated) {
            CaptureStore.recent().prefix(CaptureStore.maxItems).compactMap { url -> Item? in
                // Drain after every file: making a PNG thumbnail decodes the whole image, and
                // without this the decoded bitmaps of all 20 pile up until the loop ends.
                autoreleasepool {
                    guard let thumbnail = CaptureStore.thumbnail(for: url, maxPixelSize: pixels) else { return nil }
                    return Item(url: url, thumbnail: thumbnail)
                }
            }
        }.value
        items = loaded
        self.loaded = true
    }
}

private struct HistoryView: View {
    static let size = CGSize(width: 680, height: 468)

    let model: HistoryModel
    let onPick: (URL) -> Void

    private let columns = Array(repeating: GridItem(.fixed(120), spacing: 10), count: 5)

    var body: some View {
        ZStack {
            if model.items.isEmpty {
                Text(model.loaded ? "No captures yet" : "")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(model.items) { item in
                        Thumbnail(
                            item: item,
                            hovering: model.hovered == item.url,
                            onHover: { inside in
                                if inside {
                                    model.hovered = item.url
                                } else if model.hovered == item.url {
                                    model.hovered = nil
                                }
                            },
                            action: { onPick(item.url) }
                        )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(20)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial)
        .ignoresSafeArea()
        .task { await model.load() }
    }
}

private struct Thumbnail: View {
    let item: HistoryModel.Item
    let hovering: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(decorative: item.thumbnail, scale: 2)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 88)
                .padding(4)
                .background(.quaternary.opacity(hovering ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: hovering ? 2 : 0)
                }
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .help(item.url.lastPathComponent)
    }
}
