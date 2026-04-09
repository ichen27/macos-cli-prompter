import AppKit
import Carbon.HIToolbox

final class HotkeyRecorderView: NSView {
    var onHotkeyChanged: ((UInt32, UInt32, String) -> Void)?  // keyCode, modifiers, display string

    private let label = NSTextField(labelWithString: "")
    private let recordButton = NSButton()
    private var isRecording = false
    private var localMonitor: Any?

    private var currentKeyCode: UInt32 = UInt32(kVK_ANSI_C)
    private var currentModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        recordButton.title = "Record"
        recordButton.bezelStyle = .rounded
        recordButton.font = .systemFont(ofSize: 11)
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recordButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            recordButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            recordButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
        ])

        loadSaved()
        updateLabel()
    }

    private func loadSaved() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hotkeyKeyCode") != nil {
            currentKeyCode = UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
            currentModifiers = UInt32(defaults.integer(forKey: "hotkeyModifiers"))
        }
    }

    func updateLabel() {
        label.stringValue = displayString(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        recordButton.title = "Cancel"
        label.stringValue = "Press a key combo..."
        label.textColor = .systemOrange

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier
            guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else {
                return event
            }

            let keyCode = UInt32(event.keyCode)
            var carbonMods: UInt32 = 0
            if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if flags.contains(.control) { carbonMods |= UInt32(controlKey) }

            self.currentKeyCode = keyCode
            self.currentModifiers = carbonMods

            UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
            UserDefaults.standard.set(Int(carbonMods), forKey: "hotkeyModifiers")

            let display = self.displayString(keyCode: keyCode, modifiers: carbonMods)
            self.onHotkeyChanged?(keyCode, carbonMods, display)
            self.stopRecording()

            return nil // consume
        }
    }

    private func stopRecording() {
        isRecording = false
        recordButton.title = "Record"
        label.textColor = .labelColor
        updateLabel()

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(keyCode))
        return parts.joined()
    }

    private func keyName(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Esc",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
