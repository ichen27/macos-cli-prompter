import AppKit
import Carbon.HIToolbox

private func debugLog(_ msg: String) {
    let logFile = NSHomeDirectory() + "/ClaudePrompt/debug.log"
    let line = "\(Date()): [HotkeyManager] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let fh = FileHandle(forWritingAtPath: logFile) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: logFile))
        }
    }
}

// C function callback for Carbon event handler
private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    debugLog("Carbon handler fired!")
    DispatchQueue.main.async {
        HotkeyManager.shared.onTrigger?()
    }
    return noErr
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var currentKeyCode: UInt32 = UInt32(kVK_ANSI_C)
    private var currentModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    var onTrigger: (() -> Void)?

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hotkeyKeyCode") != nil {
            currentKeyCode = UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
            currentModifiers = UInt32(defaults.integer(forKey: "hotkeyModifiers"))
        }
    }

    func start() {
        debugLog("start() called, AXIsProcessTrusted=\(AXIsProcessTrusted())")

        let carbonOK = registerCarbonHotkey()
        debugLog("Carbon hotkey: \(carbonOK ? "OK" : "FAILED")")

        registerNSEventMonitors()
        debugLog("NSEvent monitors registered")
    }

    func reregister(keyCode: UInt32, modifiers: UInt32) {
        currentKeyCode = keyCode
        currentModifiers = modifiers

        // Unregister old Carbon hotkey
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        // Unregister old NSEvent monitors
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }

        // Re-register with new key
        let carbonOK = registerCarbonHotkey()
        registerNSEventMonitors()
        debugLog("Reregistered hotkey: keyCode=\(keyCode) mods=\(modifiers) carbon=\(carbonOK)")
    }

    // MARK: - Carbon Hot Key

    private func registerCarbonHotkey() -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5044), id: 1)

        let status = RegisterEventHotKey(
            currentKeyCode,
            currentModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            debugLog("RegisterEventHotKey failed: \(status)")
            return false
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &eventType,
            nil,
            nil
        )

        guard installStatus == noErr else {
            debugLog("InstallEventHandler failed: \(installStatus)")
            return false
        }

        return true
    }

    // MARK: - NSEvent Monitors

    private func registerNSEventMonitors() {
        // Global monitor: fires when OTHER apps are active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor: fires when THIS app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isHotkey(event) == true {
                self?.handleKeyEvent(event)
                return nil // consume
            }
            return event
        }
    }

    private func isHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var requiredFlags: NSEvent.ModifierFlags = []
        if currentModifiers & UInt32(cmdKey) != 0 { requiredFlags.insert(.command) }
        if currentModifiers & UInt32(shiftKey) != 0 { requiredFlags.insert(.shift) }
        if currentModifiers & UInt32(optionKey) != 0 { requiredFlags.insert(.option) }
        if currentModifiers & UInt32(controlKey) != 0 { requiredFlags.insert(.control) }
        return flags.contains(requiredFlags) && event.keyCode == UInt16(currentKeyCode)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard isHotkey(event) else { return }
        debugLog("Hotkey detected via NSEvent! keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue)")
        DispatchQueue.main.async {
            self.onTrigger?()
        }
    }

    // MARK: - Text Capture

    func captureSelectedText(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount

        simulateCopy()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let newText: String?
            if pasteboard.changeCount != oldChangeCount {
                newText = pasteboard.string(forType: .string)
            } else {
                newText = nil
            }
            debugLog("captureSelectedText: changeCount \(oldChangeCount)->\(pasteboard.changeCount), text=\(newText != nil ? "'\(newText!.prefix(30))...'" : "nil")")
            completion(newText)
        }
    }

    private func simulateCopy() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
