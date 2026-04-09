import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onTrigger: (() -> Void)?

    private init() {}

    func start() {
        guard AXIsProcessTrusted() else {
            promptAccessibility()
            return
        }
        registerEventTap()
    }

    func captureSelectedText(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.pasteboardItems?.compactMap { item -> (String, NSPasteboard.PasteboardType)? in
            for type in item.types {
                if let data = item.string(forType: type) {
                    return (data, type)
                }
            }
            return nil
        }

        pasteboard.clearContents()

        simulateCopy()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let selectedText = pasteboard.string(forType: .string)

            pasteboard.clearContents()
            if let oldContents = oldContents, !oldContents.isEmpty {
                for (content, type) in oldContents {
                    pasteboard.setString(content, forType: type)
                }
            }

            completion(selectedText)
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

    private func registerEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard type == .keyDown else { return Unmanaged.passRetained(event) }

            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            // ⌘⇧C = Command + Shift + C (keycode 8)
            let hasCommand = flags.contains(.maskCommand)
            let hasShift = flags.contains(.maskShift)
            let isC = keycode == Int64(kVK_ANSI_C)

            if hasCommand && hasShift && isC {
                DispatchQueue.main.async {
                    HotkeyManager.shared.onTrigger?()
                }
                return nil // consume the event
            }

            return Unmanaged.passRetained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        )

        guard let eventTap = eventTap else {
            promptAccessibility()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func promptAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "ClaudePrompt needs Accessibility permission to capture global hotkeys and selected text.\n\nPlease enable it in System Settings > Privacy & Security > Accessibility."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
