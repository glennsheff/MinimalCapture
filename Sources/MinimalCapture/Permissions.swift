import AppKit
import SwiftUI

/// Module 1: Screen Recording permission gate.
/// Shows a small window until access is granted, polling once a second.
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var timer: Timer?
    private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
    }

    func show() {
        if let window {
            bringToFront(window)
            return
        }

        let view = OnboardingView(
            request: { [weak self] in
                self?.stepBack()
                CGRequestScreenCaptureAccess()
            },
            openSettings: { [weak self] in
                self?.stepBack()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            },
            quit: { NSApp.terminate(nil) }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // ARC owns the window; see the note in SelectionOverlay about isReleasedWhenClosed.
        window.isReleasedWhenClosed = false
        window.title = "MinimalCapture"
        window.contentViewController = NSHostingController(rootView: view)
        window.delegate = self
        // A menu bar app is not guaranteed to become the active app when it asks, so the
        // window floats above other apps' windows instead of relying on activation.
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        self.window = window

        bringToFront(window)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Once the user has clicked a button, the next thing they need is the macOS prompt or
    /// System Settings. Stop floating and move behind so this window does not cover them.
    private func stepBack() {
        window?.level = .normal
        window?.orderBack(nil)
    }

    private func bringToFront(_ window: NSWindow) {
        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless() // shows on top even if activation was refused
    }

    private func poll() {
        guard CGPreflightScreenCaptureAccess() else { return }
        teardown()
        onGranted()
    }

    private func teardown() {
        timer?.invalidate()
        timer = nil
        window?.delegate = nil
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        // User closed the window without granting: stop polling and drop the window.
        timer?.invalidate()
        timer = nil
        window = nil
    }
}

private struct OnboardingView: View {
    let request: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Screen Recording access needed", systemImage: "camera.viewfinder")
                .font(.title3.weight(.semibold))

            Text("MinimalCapture needs Screen Recording permission to capture what is on your screen. Nothing is recorded in the background; pixels are only read when you press a capture shortcut.")
                .fixedSize(horizontal: false, vertical: true)

            Text("If macOS asks you to quit and reopen the app after you allow it, do that. This window closes by itself once access is granted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Button("Quit", action: quit)
                Spacer()
                Button("Open System Settings", action: openSettings)
                Button("Request Access", action: request)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 260)
    }
}
