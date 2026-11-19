import AppKit
import Carbon.HIToolbox

/// Module 2: global hotkeys through Carbon's RegisterEventHotKey.
/// No event tap and no global monitor, so no Accessibility permission is needed
/// and Secure Event Input does not block the shortcuts.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    enum Key {
        static let three = kVK_ANSI_3
        static let four = kVK_ANSI_4
        static let v = kVK_ANSI_V
        static let escape = kVK_Escape
    }

    enum Modifier {
        static let commandShift = cmdKey | shiftKey
        static let none = 0
    }

    private static let signature: OSType = 0x4D43_4150 // 'MCAP'

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Registers a hotkey. Returns a token for `unregister`, or nil if the system refused it
    /// (usually because another app already owns the combination).
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> UInt32? {
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            NSLog("MinimalCapture: could not register hotkey (keyCode %d, status %d)", keyCode, status)
            return nil
        }
        refs[id] = ref
        handlers[id] = handler
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventCallback, 1, &spec, nil, &eventHandler)
    }
}

/// C callback. Carbon delivers hotkey events on the main thread.
private nonisolated func hotKeyEventCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        HotKeyCenter.shared.fire(id)
    }
    return noErr
}
