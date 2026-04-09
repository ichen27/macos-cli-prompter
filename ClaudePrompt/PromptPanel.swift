import AppKit

protocol PromptPanelDelegate: AnyObject {
    func promptPanel(_ panel: PromptPanel, didSubmitPrompt prompt: String)
    func promptPanelDidCancel(_ panel: PromptPanel)
}

final class PromptPanel: NSPanel, NSTextFieldDelegate {
    weak var promptDelegate: PromptPanelDelegate?

    private let textField = NSTextField()
    private let charCountLabel = NSTextField(labelWithString: "")
    private let escLabel = NSTextField(labelWithString: "esc")
    private let sendButton = NSButton()

    private var selectedTextLength: Int = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow

        setupUI()
    }

    private func setupUI() {
        let contentRect = self.contentRect(forFrameRect: self.frame)
        let container = NSVisualEffectView(frame: contentRect)
        container.autoresizingMask = [.width, .height]
        container.material = NSVisualEffectView.Material.popover
        container.state = NSVisualEffectView.State.active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        contentView = container

        // Text field
        textField.placeholderString = "What should Claude do?"
        textField.isBordered = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 14)
        textField.backgroundColor = .clear
        textField.textColor = .labelColor
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textField)

        // Bottom row container
        let bottomRow = NSView()
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bottomRow)

        // Char count
        charCountLabel.font = .systemFont(ofSize: 11)
        charCountLabel.textColor = .tertiaryLabelColor
        charCountLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomRow.addSubview(charCountLabel)

        // Esc label
        escLabel.font = .systemFont(ofSize: 11)
        escLabel.textColor = .tertiaryLabelColor
        escLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomRow.addSubview(escLabel)

        // Send button
        sendButton.title = "\u{23CE}"
        sendButton.bezelStyle = .recessed
        sendButton.isBordered = true
        sendButton.font = .systemFont(ofSize: 12, weight: .medium)
        sendButton.target = self
        sendButton.action = #selector(submitAction)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.wantsLayer = true
        sendButton.contentTintColor = .white
        sendButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        sendButton.layer?.cornerRadius = 4
        bottomRow.addSubview(sendButton)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            bottomRow.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 10),
            bottomRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            bottomRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            bottomRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            bottomRow.heightAnchor.constraint(equalToConstant: 22),

            charCountLabel.leadingAnchor.constraint(equalTo: bottomRow.leadingAnchor),
            charCountLabel.centerYAnchor.constraint(equalTo: bottomRow.centerYAnchor),

            sendButton.trailingAnchor.constraint(equalTo: bottomRow.trailingAnchor),
            sendButton.centerYAnchor.constraint(equalTo: bottomRow.centerYAnchor),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            escLabel.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            escLabel.centerYAnchor.constraint(equalTo: bottomRow.centerYAnchor),
        ])
    }

    func show(selectedTextLength: Int) {
        self.selectedTextLength = selectedTextLength
        textField.stringValue = ""
        updateCharCount()

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2 + screenFrame.height * 0.15
        setFrameOrigin(NSPoint(x: x, y: y))

        makeKeyAndOrderFront(nil)
        textField.becomeFirstResponder()

        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        orderOut(nil)
        textField.stringValue = ""
    }

    private func updateCharCount() {
        if selectedTextLength > 0 {
            charCountLabel.stringValue = "\(selectedTextLength) chars selected"
        } else {
            charCountLabel.stringValue = ""
        }
    }

    @objc private func submitAction() {
        let prompt = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        promptDelegate?.promptPanel(self, didSubmitPrompt: prompt)
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            submitAction()
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            promptDelegate?.promptPanelDidCancel(self)
            return true
        }
        return false
    }

    // Allow the panel to become key even though it's borderless
    override var canBecomeKey: Bool { true }
}
