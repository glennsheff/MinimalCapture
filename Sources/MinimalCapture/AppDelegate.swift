import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let folderLabelItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var keepLatestItem = NSMenuItem()
    private var loginItem = NSMenuItem()
    private var onboarding: OnboardingController?
    private var overlay: SelectionOverlay?
    private var history: HistoryPanelController?
    private var hotKeysInstalled = false
    private var captureInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        if CGPreflightScreenCaptureAccess() {
            installHotKeys()
        } else {
            showOnboarding()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "MinimalCapture")

        let menu = NSMenu()
        menu.addItem(menuItem("Capture Full Screen", #selector(captureFullScreen), key: "3"))
        menu.addItem(menuItem("Capture Area", #selector(captureArea), key: "4"))
        menu.addItem(menuItem("Show History", #selector(toggleHistory), key: "v"))
        menu.addItem(.separator())
        folderLabelItem.isEnabled = false
        menu.addItem(folderLabelItem)
        menu.addItem(menuItem("Open Save Folder", #selector(openFolder), key: nil))
        menu.addItem(menuItem("Change Save Folder…", #selector(changeFolder), key: nil))
        keepLatestItem = menuItem("Keep Only Latest \(CaptureStore.maxItems)", #selector(toggleKeepLatest), key: nil)
        menu.addItem(keepLatestItem)
        menu.addItem(.separator())
        loginItem = menuItem("Start at Login", #selector(toggleStartAtLogin), key: nil)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit MinimalCapture", #selector(quit), key: nil))
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Refreshes the checkmarks and folder name each time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        folderLabelItem.title = "Saving to: \(FileManager.default.displayName(atPath: CaptureStore.directory.path))"
        keepLatestItem.state = CaptureStore.keepOnlyLatest ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Settings

    @objc private func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = CaptureStore.directory
        panel.prompt = "Save Here"
        panel.message = "Choose where MinimalCapture saves screenshots."
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            CaptureStore.directory = url
        }
    }

    @objc private func toggleKeepLatest() {
        CaptureStore.keepOnlyLatest.toggle()
    }

    @objc private func toggleStartAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the Start at Login setting"
            alert.informativeText = error.localizedDescription
            NSApp.activate()
            alert.runModal()
        }
    }

    /// `key` is shown as a ⇧⌘ hint next to the item; the real shortcut is the Carbon hotkey.
    private func menuItem(_ title: String, _ action: Selector, key: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key ?? "")
        if key != nil { item.keyEquivalentModifierMask = [.command, .shift] }
        item.target = self
        return item
    }

    // MARK: - Permission

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingController { [weak self] in
                self?.onboarding = nil
                self?.installHotKeys()
            }
        }
        onboarding?.show()
    }

    private func hasPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            installHotKeys()
            return true
        }
        showOnboarding()
        return false
    }

    // MARK: - Hotkeys

    private func installHotKeys() {
        guard !hotKeysInstalled else { return }
        hotKeysInstalled = true

        let center = HotKeyCenter.shared
        let combo = HotKeyCenter.Modifier.commandShift
        center.register(keyCode: HotKeyCenter.Key.three, modifiers: combo) { [weak self] in self?.captureFullScreen() }
        center.register(keyCode: HotKeyCenter.Key.four, modifiers: combo) { [weak self] in self?.captureArea() }
        center.register(keyCode: HotKeyCenter.Key.v, modifiers: combo) { [weak self] in self?.toggleHistory() }
    }

    // MARK: - Actions

    @objc private func captureFullScreen() {
        guard hasPermission() else { return }
        // The screen the pointer is on.
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        capture(screen: screen, rect: nil)
    }

    @objc private func captureArea() {
        guard hasPermission() else { return }
        if let overlay {
            // Pressing the shortcut again while selecting cancels.
            overlay.cancel()
            return
        }
        history?.close()

        let overlay = SelectionOverlay { [weak self] selection in
            self?.overlay = nil
            if let selection {
                self?.capture(screen: selection.screen, rect: selection.rect)
            }
        }
        self.overlay = overlay
        overlay.begin()
    }

    @objc private func toggleHistory() {
        if let history {
            history.close()
            return
        }
        let controller = HistoryPanelController { [weak self] in
            self?.history = nil
        }
        history = controller
        controller.show()
    }

    @objc private func openFolder() {
        let directory = CaptureStore.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Capture pipeline

    private func capture(screen: NSScreen, rect: NSRect?) {
        guard !captureInFlight else { return }
        captureInFlight = true

        Task {
            defer { captureInFlight = false }
            do {
                let capture = try await CaptureEngine.capture(screen: screen, localRect: rect)

                // Compress once, off the main thread; the uncompressed bitmap is released
                // as soon as this returns.
                let png = try await Task.detached(priority: .userInitiated) {
                    try CaptureStore.pngData(capture.image, scale: capture.scale)
                }.value

                // Clipboard first, so paste works as early as possible.
                Clipboard.copyPNG(png)
                Self.playShutter()

                Task.detached(priority: .utility) {
                    do {
                        try CaptureStore.save(png)
                    } catch {
                        NSLog("MinimalCapture: could not save capture: %@", String(describing: error))
                    }
                }
            } catch {
                NSLog("MinimalCapture: capture failed: %@", String(describing: error))
                NSSound.beep()
            }
        }
    }

    private static func playShutter() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}
