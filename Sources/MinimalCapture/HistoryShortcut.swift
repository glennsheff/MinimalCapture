import AppKit
import Carbon.HIToolbox

/// The user-configurable shortcut that opens the history panel.
struct Shortcut: Equatable {
    let keyCode: Int
    /// Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey).
    let modifiers: Int
    /// Name of the key without modifiers, e.g. "V", "F6", "Space".
    let keyName: String

    static let defaultHistory = Shortcut(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey, keyName: "V")

    /// For display, e.g. "⇧⌘V".
    var display: String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + keyName
    }

    /// The same modifiers as AppKit flags, for showing the hint in a menu item.
    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    /// Builds a shortcut from a key press, or nil if it is not usable as a global shortcut.
    /// At least one of ⌘, ⌃ or ⌥ is required so ordinary typing can never trigger it.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }

        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }

        self.keyCode = Int(event.keyCode)
        self.modifiers = carbon
        self.keyName = Self.name(for: event)
    }

    init(keyCode: Int, modifiers: Int, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    private static func name(for event: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
            kVK_ForwardDelete: "Forward Delete", kVK_Escape: "Esc",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(event.keyCode)] { return name }
        // The character the key produces with no modifiers held.
        if let base = event.characters(byApplyingModifiers: []), !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return base.uppercased()
        }
        return "Key \(event.keyCode)"
    }
}

/// Persistence for the history shortcut.
enum HistoryShortcutSetting {
    private static let codeKey = "historyShortcutKeyCode"
    private static let modifiersKey = "historyShortcutModifiers"
    private static let nameKey = "historyShortcutKeyName"
    private static let offKey = "historyShortcutOff"

    /// The saved shortcut, the default if none was ever chosen, or nil if turned off.
    static var current: Shortcut? {
        get {
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: offKey) { return nil }
            guard defaults.object(forKey: codeKey) != nil,
                  let name = defaults.string(forKey: nameKey) else {
                return .defaultHistory
            }
            return Shortcut(
                keyCode: defaults.integer(forKey: codeKey),
                modifiers: defaults.integer(forKey: modifiersKey),
                keyName: name
            )
        }
        set {
            let defaults = UserDefaults.standard
            if let newValue {
                defaults.set(false, forKey: offKey)
                defaults.set(newValue.keyCode, forKey: codeKey)
                defaults.set(newValue.modifiers, forKey: modifiersKey)
                defaults.set(newValue.keyName, forKey: nameKey)
            } else {
                defaults.set(true, forKey: offKey)
            }
        }
    }
}

/// A small modal dialog that waits for the user to press a key combination.
enum ShortcutRecorder {
    enum Result {
        case set(Shortcut)
        case turnOff
        case reset
        case cancel
    }

    static func run(current: Shortcut?) -> Result {
        let alert = NSAlert()
        alert.messageText = "Change History Shortcut"
        alert.informativeText = "Press the new key combination now. It must include ⌘, ⌃ or ⌥."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Turn Off")
        alert.addButton(withTitle: "Reset to \(Shortcut.defaultHistory.display)")

        let field = RecorderField(frame: NSRect(x: 0, y: 0, width: 240, height: 36))
        field.placeholder = current.map { "Current: \($0.display)" } ?? "Current: off"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.level = .floating

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if let recorded = field.recorded { return .set(recorded) }
        switch response {
        case .alertSecondButtonReturn: return .turnOff
        case .alertThirdButtonReturn: return .reset
        default: return .cancel
        }
    }
}

private final class RecorderField: NSView {
    var placeholder = ""
    private(set) var recorded: Shortcut?

    override var acceptsFirstResponder: Bool { true }

    // ⌘ combinations arrive here before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self else { return false }
        return record(event)
    }

    override func keyDown(with event: NSEvent) {
        if !record(event) { super.keyDown(with: event) }
    }

    private func record(_ event: NSEvent) -> Bool {
        guard let shortcut = Shortcut(event: event) else { return false }
        recorded = shortcut
        needsDisplay = true
        NSApp.stopModal()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        box.fill()
        NSColor.controlAccentColor.setStroke()
        box.lineWidth = 2
        box.stroke()

        let text = recorded?.display ?? placeholder
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: recorded == nil ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
