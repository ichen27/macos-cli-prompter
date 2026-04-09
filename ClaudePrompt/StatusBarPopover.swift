import AppKit

protocol StatusBarPopoverDelegate: AnyObject {
    func statusBarPopover(_ popover: StatusBarPopover, didSubmitPrompt prompt: String, context: String?)
    func statusBarPopoverDidClearHistory(_ popover: StatusBarPopover)
}

final class StatusBarPopover: NSObject {
    weak var delegate: StatusBarPopoverDelegate?

    private let popover = NSPopover()
    private let viewController = StatusBarViewController()

    override init() {
        super.init()
        popover.contentViewController = viewController
        popover.behavior = .transient
        popover.animates = true
        viewController.onSubmit = { [weak self] prompt, context in
            guard let self = self else { return }
            self.popover.close()
            self.delegate?.statusBarPopover(self, didSubmitPrompt: prompt, context: context)
        }
        viewController.onClearHistory = { [weak self] in
            guard let self = self else { return }
            self.delegate?.statusBarPopoverDidClearHistory(self)
            self.viewController.reloadHistory()
        }
    }

    func toggle(relativeTo button: NSView) {
        if popover.isShown {
            popover.close()
        } else {
            viewController.updateContext(NSPasteboard.general.string(forType: .string))
            viewController.reloadHistory()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Focus the text field after popover is shown
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.viewController.focusPromptField()
            }
        }
    }

    func showWithContext(_ text: String?, relativeTo button: NSView) {
        viewController.updateContext(text)
        viewController.reloadHistory()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.viewController.focusPromptField()
        }
    }

    var isShown: Bool { popover.isShown }

    func close() { popover.close() }
}

// MARK: - View Controller

final class StatusBarViewController: NSViewController, NSTextFieldDelegate {
    var onSubmit: ((String, String?) -> Void)?
    var onClearHistory: (() -> Void)?

    private let contextLabel = NSTextField(labelWithString: "Copied Text")
    private let contextView = NSScrollView()
    private let contextText = NSTextView()
    private let promptField = NSTextField()
    private let sendButton = NSButton()
    private let historyLabel = NSTextField(labelWithString: "Recent")
    private let historyStack = NSStackView()
    private let clearButton = NSButton()
    private let separator = NSBox()
    private let separator2 = NSBox()
    private let quitButton = NSButton()

    private var currentContext: String?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
        self.view = container
        setupUI(in: container)
    }

    private func setupUI(in container: NSView) {
        // Context label
        contextLabel.font = .systemFont(ofSize: 11, weight: .medium)
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.stringValue = "COPIED TEXT"
        contextLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contextLabel)

        // Context scroll view with text
        contextView.translatesAutoresizingMaskIntoConstraints = false
        contextView.hasVerticalScroller = true
        contextView.hasHorizontalScroller = false
        contextView.borderType = .noBorder
        contextView.drawsBackground = false

        contextText.isEditable = false
        contextText.isSelectable = true
        contextText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        contextText.textColor = .labelColor
        contextText.backgroundColor = .clear
        contextText.isVerticallyResizable = true
        contextText.isHorizontallyResizable = false
        contextText.textContainer?.widthTracksTextView = true
        contextText.textContainer?.containerSize = NSSize(width: 328, height: CGFloat.greatestFiniteMagnitude)

        contextView.documentView = contextText
        container.addSubview(contextView)

        // Separator
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        // Prompt field
        promptField.placeholderString = "What should Claude do?"
        promptField.font = .systemFont(ofSize: 14)
        promptField.focusRingType = .none
        promptField.bezelStyle = .roundedBezel
        promptField.delegate = self
        promptField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(promptField)

        // Send button
        sendButton.title = "Send ⏎"
        sendButton.bezelStyle = .rounded
        sendButton.font = .systemFont(ofSize: 12, weight: .medium)
        sendButton.target = self
        sendButton.action = #selector(submitAction)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.keyEquivalent = "\r"
        container.addSubview(sendButton)

        // Separator 2
        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator2)

        // History label
        historyLabel.font = .systemFont(ofSize: 11, weight: .medium)
        historyLabel.textColor = .secondaryLabelColor
        historyLabel.stringValue = "RECENT PROMPTS"
        historyLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(historyLabel)

        // History stack
        historyStack.orientation = .vertical
        historyStack.alignment = .leading
        historyStack.spacing = 2
        historyStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(historyStack)

        // Clear button
        clearButton.title = "Clear History"
        clearButton.bezelStyle = .inline
        clearButton.font = .systemFont(ofSize: 11)
        clearButton.target = self
        clearButton.action = #selector(clearHistoryAction)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(clearButton)

        // Quit button
        quitButton.title = "Quit"
        quitButton.bezelStyle = .inline
        quitButton.font = .systemFont(ofSize: 11)
        quitButton.target = self
        quitButton.action = #selector(quitAction)
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(quitButton)

        NSLayoutConstraint.activate([
            // Context label
            contextLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            contextLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            // Context text view
            contextView.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 6),
            contextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            contextView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            contextView.heightAnchor.constraint(equalToConstant: 80),

            // Separator
            separator.topAnchor.constraint(equalTo: contextView.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            // Prompt field
            promptField.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 10),
            promptField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            promptField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            promptField.heightAnchor.constraint(equalToConstant: 28),

            // Send button
            sendButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            sendButton.centerYAnchor.constraint(equalTo: promptField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 70),

            // Separator 2
            separator2.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 10),
            separator2.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            separator2.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            // History label
            historyLabel.topAnchor.constraint(equalTo: separator2.bottomAnchor, constant: 10),
            historyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            // History stack
            historyStack.topAnchor.constraint(equalTo: historyLabel.bottomAnchor, constant: 6),
            historyStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            historyStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            // Clear + Quit row
            clearButton.topAnchor.constraint(equalTo: historyStack.bottomAnchor, constant: 10),
            clearButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            clearButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            quitButton.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),
            quitButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
    }

    func updateContext(_ text: String?) {
        currentContext = text
        if let text = text, !text.isEmpty {
            contextText.string = text
            contextLabel.stringValue = "COPIED TEXT (\(text.count) chars)"
            contextView.isHidden = false
            contextLabel.isHidden = false
            separator.isHidden = false
        } else {
            contextText.string = ""
            contextLabel.stringValue = "COPIED TEXT"
            contextView.isHidden = true
            contextLabel.isHidden = true
            separator.isHidden = true
        }
    }

    func reloadHistory() {
        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let items = PromptHistoryManager.shared.history
        if items.isEmpty {
            historyLabel.isHidden = true
            clearButton.isHidden = true
        } else {
            historyLabel.isHidden = false
            clearButton.isHidden = false
            for (index, prompt) in items.prefix(5).enumerated() {
                let truncated = prompt.count > 60 ? String(prompt.prefix(57)) + "..." : prompt
                let button = NSButton(title: truncated, target: self, action: #selector(historyItemClicked(_:)))
                button.bezelStyle = .inline
                button.font = .systemFont(ofSize: 12)
                button.tag = index
                button.alignment = .left
                button.translatesAutoresizingMaskIntoConstraints = false
                historyStack.addArrangedSubview(button)
                button.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
            }
        }
    }

    func focusPromptField() {
        promptField.stringValue = ""
        view.window?.makeFirstResponder(promptField)
    }

    @objc private func submitAction() {
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        promptField.stringValue = ""
        onSubmit?(prompt, currentContext)
    }

    @objc private func clearHistoryAction() {
        onClearHistory?()
    }

    @objc private func historyItemClicked(_ sender: NSButton) {
        let items = PromptHistoryManager.shared.history
        guard sender.tag < items.count else { return }
        let prompt = items[sender.tag]
        onSubmit?(prompt, currentContext)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            submitAction()
            return true
        }
        return false
    }
}
