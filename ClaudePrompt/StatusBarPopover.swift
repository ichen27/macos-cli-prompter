import AppKit

protocol StatusBarPopoverDelegate: AnyObject {
    func statusBarPopover(_ popover: StatusBarPopover, didSubmitPrompt prompt: String, context: String?)
    func statusBarPopoverDidClearHistory(_ popover: StatusBarPopover)
    func statusBarPopoverDidChangeHotkey(_ popover: StatusBarPopover, keyCode: UInt32, modifiers: UInt32)
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
        viewController.onHotkeyChanged = { [weak self] keyCode, modifiers, _ in
            guard let self = self else { return }
            self.delegate?.statusBarPopoverDidChangeHotkey(self, keyCode: keyCode, modifiers: modifiers)
        }
    }

    func toggle(relativeTo button: NSView) {
        if popover.isShown {
            popover.close()
        } else {
            viewController.updateContext(NSPasteboard.general.string(forType: .string))
            viewController.reloadHistory()
            viewController.refreshPermissions()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.viewController.focusPromptField()
            }
        }
    }

    func showWithContext(_ text: String?, relativeTo button: NSView) {
        viewController.updateContext(text)
        viewController.reloadHistory()
        viewController.refreshPermissions()
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
    var onHotkeyChanged: ((UInt32, UInt32, String) -> Void)?

    // Tab buttons
    private let promptTab = NSButton()
    private let settingsTab = NSButton()

    // Prompt view
    private let promptContainer = NSView()
    private let contextLabel = NSTextField(labelWithString: "")
    private let contextView = NSScrollView()
    private let contextText = NSTextView()
    private let promptField = NSTextField()
    private let sendButton = NSButton()
    private let separator = NSBox()
    private let separator2 = NSBox()
    private let historyLabel = NSTextField(labelWithString: "")
    private let historyStack = NSStackView()
    private let clearButton = NSButton()

    // Settings view
    private let settingsContainer = NSView()
    private let hotkeyLabel = NSTextField(labelWithString: "")
    private let hotkeyRecorder = HotkeyRecorderView()
    private let permissionsLabel = NSTextField(labelWithString: "")
    private let accessibilityRow = PermissionRow(title: "Accessibility", detail: "Required for global hotkey")
    private let automationRow = PermissionRow(title: "Automation (iTerm)", detail: "Required to send commands to iTerm")

    // Footer
    private let quitButton = NSButton()

    private var currentContext: String?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 420))
        self.view = container
        setupTabs(in: container)
        setupPromptView(in: container)
        setupSettingsView(in: container)
        setupFooter(in: container)
        showPromptTab()
    }

    // MARK: - Tabs

    private func setupTabs(in container: NSView) {
        promptTab.title = "Prompt"
        promptTab.bezelStyle = .toolbar
        promptTab.setButtonType(.pushOnPushOff)
        promptTab.state = .on
        promptTab.font = .systemFont(ofSize: 12, weight: .medium)
        promptTab.target = self
        promptTab.action = #selector(showPromptTab)
        promptTab.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(promptTab)

        settingsTab.title = "Settings"
        settingsTab.bezelStyle = .toolbar
        settingsTab.setButtonType(.pushOnPushOff)
        settingsTab.state = .off
        settingsTab.font = .systemFont(ofSize: 12, weight: .medium)
        settingsTab.target = self
        settingsTab.action = #selector(showSettingsTab)
        settingsTab.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(settingsTab)

        NSLayoutConstraint.activate([
            promptTab.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            promptTab.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            promptTab.widthAnchor.constraint(equalToConstant: 80),

            settingsTab.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            settingsTab.leadingAnchor.constraint(equalTo: promptTab.trailingAnchor, constant: 4),
            settingsTab.widthAnchor.constraint(equalToConstant: 80),
        ])
    }

    // MARK: - Prompt View

    private func setupPromptView(in container: NSView) {
        promptContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(promptContainer)

        contextLabel.font = .systemFont(ofSize: 11, weight: .medium)
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.stringValue = "COPIED TEXT"
        contextLabel.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(contextLabel)

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
        contextText.textContainer?.containerSize = NSSize(width: 348, height: CGFloat.greatestFiniteMagnitude)
        contextView.documentView = contextText
        promptContainer.addSubview(contextView)

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(separator)

        promptField.placeholderString = "What should Claude do?"
        promptField.font = .systemFont(ofSize: 14)
        promptField.focusRingType = .none
        promptField.bezelStyle = .roundedBezel
        promptField.delegate = self
        promptField.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(promptField)

        sendButton.title = "Send ⏎"
        sendButton.bezelStyle = .rounded
        sendButton.font = .systemFont(ofSize: 12, weight: .medium)
        sendButton.target = self
        sendButton.action = #selector(submitAction)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.keyEquivalent = "\r"
        promptContainer.addSubview(sendButton)

        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(separator2)

        historyLabel.font = .systemFont(ofSize: 11, weight: .medium)
        historyLabel.textColor = .secondaryLabelColor
        historyLabel.stringValue = "RECENT PROMPTS"
        historyLabel.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(historyLabel)

        historyStack.orientation = .vertical
        historyStack.alignment = .leading
        historyStack.spacing = 2
        historyStack.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(historyStack)

        clearButton.title = "Clear History"
        clearButton.bezelStyle = .inline
        clearButton.font = .systemFont(ofSize: 11)
        clearButton.target = self
        clearButton.action = #selector(clearHistoryAction)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(clearButton)

        NSLayoutConstraint.activate([
            promptContainer.topAnchor.constraint(equalTo: promptTab.bottomAnchor, constant: 10),
            promptContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            promptContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            contextLabel.topAnchor.constraint(equalTo: promptContainer.topAnchor),
            contextLabel.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 16),

            contextView.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 6),
            contextView.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 16),
            contextView.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: -16),
            contextView.heightAnchor.constraint(equalToConstant: 80),

            separator.topAnchor.constraint(equalTo: contextView.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: -16),

            promptField.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 10),
            promptField.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 16),
            promptField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            promptField.heightAnchor.constraint(equalToConstant: 28),

            sendButton.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: -16),
            sendButton.centerYAnchor.constraint(equalTo: promptField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 70),

            separator2.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 10),
            separator2.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 16),
            separator2.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: -16),

            historyLabel.topAnchor.constraint(equalTo: separator2.bottomAnchor, constant: 10),
            historyLabel.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 16),

            historyStack.topAnchor.constraint(equalTo: historyLabel.bottomAnchor, constant: 6),
            historyStack.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 16),
            historyStack.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: -16),

            clearButton.topAnchor.constraint(equalTo: historyStack.bottomAnchor, constant: 10),
            clearButton.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 16),
            clearButton.bottomAnchor.constraint(equalTo: promptContainer.bottomAnchor),
        ])
    }

    // MARK: - Settings View

    private func setupSettingsView(in container: NSView) {
        settingsContainer.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.isHidden = true
        container.addSubview(settingsContainer)

        // Hotkey section
        hotkeyLabel.font = .systemFont(ofSize: 11, weight: .medium)
        hotkeyLabel.textColor = .secondaryLabelColor
        hotkeyLabel.stringValue = "GLOBAL HOTKEY"
        hotkeyLabel.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(hotkeyLabel)

        hotkeyRecorder.translatesAutoresizingMaskIntoConstraints = false
        hotkeyRecorder.onHotkeyChanged = { [weak self] keyCode, modifiers, display in
            self?.onHotkeyChanged?(keyCode, modifiers, display)
        }
        settingsContainer.addSubview(hotkeyRecorder)

        let hotkeyHint = NSTextField(labelWithString: "Click Record then press your desired key combination")
        hotkeyHint.font = .systemFont(ofSize: 10)
        hotkeyHint.textColor = .tertiaryLabelColor
        hotkeyHint.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(hotkeyHint)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(sep)

        // Permissions section
        permissionsLabel.font = .systemFont(ofSize: 11, weight: .medium)
        permissionsLabel.textColor = .secondaryLabelColor
        permissionsLabel.stringValue = "PERMISSIONS"
        permissionsLabel.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(permissionsLabel)

        accessibilityRow.translatesAutoresizingMaskIntoConstraints = false
        accessibilityRow.onOpenSettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        settingsContainer.addSubview(accessibilityRow)

        automationRow.translatesAutoresizingMaskIntoConstraints = false
        automationRow.onOpenSettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
        settingsContainer.addSubview(automationRow)

        let permHint = NSTextField(labelWithString: "Double-copy (⌘C ⌘C) works without any permissions")
        permHint.font = .systemFont(ofSize: 10)
        permHint.textColor = .tertiaryLabelColor
        permHint.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(permHint)

        NSLayoutConstraint.activate([
            settingsContainer.topAnchor.constraint(equalTo: settingsTab.bottomAnchor, constant: 10),
            settingsContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            settingsContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            hotkeyLabel.topAnchor.constraint(equalTo: settingsContainer.topAnchor),
            hotkeyLabel.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: 16),

            hotkeyRecorder.topAnchor.constraint(equalTo: hotkeyLabel.bottomAnchor, constant: 8),
            hotkeyRecorder.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: 16),
            hotkeyRecorder.trailingAnchor.constraint(equalTo: settingsContainer.trailingAnchor, constant: -16),
            hotkeyRecorder.heightAnchor.constraint(equalToConstant: 28),

            hotkeyHint.topAnchor.constraint(equalTo: hotkeyRecorder.bottomAnchor, constant: 4),
            hotkeyHint.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: 16),

            sep.topAnchor.constraint(equalTo: hotkeyHint.bottomAnchor, constant: 14),
            sep.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: 16),
            sep.trailingAnchor.constraint(equalTo: settingsContainer.trailingAnchor, constant: -16),

            permissionsLabel.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 14),
            permissionsLabel.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: 16),

            accessibilityRow.topAnchor.constraint(equalTo: permissionsLabel.bottomAnchor, constant: 8),
            accessibilityRow.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: 16),
            accessibilityRow.trailingAnchor.constraint(equalTo: settingsContainer.trailingAnchor, constant: -16),
            accessibilityRow.heightAnchor.constraint(equalToConstant: 36),

            automationRow.topAnchor.constraint(equalTo: accessibilityRow.bottomAnchor, constant: 6),
            automationRow.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: 16),
            automationRow.trailingAnchor.constraint(equalTo: settingsContainer.trailingAnchor, constant: -16),
            automationRow.heightAnchor.constraint(equalToConstant: 36),

            permHint.topAnchor.constraint(equalTo: automationRow.bottomAnchor, constant: 10),
            permHint.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: 16),
            permHint.bottomAnchor.constraint(equalTo: settingsContainer.bottomAnchor),
        ])
    }

    // MARK: - Footer

    private func setupFooter(in container: NSView) {
        quitButton.title = "Quit"
        quitButton.bezelStyle = .inline
        quitButton.font = .systemFont(ofSize: 11)
        quitButton.target = self
        quitButton.action = #selector(quitAction)
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(quitButton)

        NSLayoutConstraint.activate([
            quitButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            quitButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            promptContainer.bottomAnchor.constraint(lessThanOrEqualTo: quitButton.topAnchor, constant: -10),
            settingsContainer.bottomAnchor.constraint(lessThanOrEqualTo: quitButton.topAnchor, constant: -10),
        ])
    }

    // MARK: - Tab switching

    @objc func showPromptTab() {
        promptTab.state = .on
        settingsTab.state = .off
        promptContainer.isHidden = false
        settingsContainer.isHidden = true
    }

    @objc private func showSettingsTab() {
        promptTab.state = .off
        settingsTab.state = .on
        promptContainer.isHidden = true
        settingsContainer.isHidden = false
        refreshPermissions()
    }

    // MARK: - Public

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
        showPromptTab()
        promptField.stringValue = ""
        view.window?.makeFirstResponder(promptField)
    }

    func refreshPermissions() {
        accessibilityRow.updateStatus(granted: AXIsProcessTrusted())

        // Check automation permission by attempting a harmless AppleScript
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: "tell application \"iTerm\" to get name")
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            let granted = error == nil
            DispatchQueue.main.async {
                self.automationRow.updateStatus(granted: granted)
            }
        }
    }

    // MARK: - Actions

    @objc private func submitAction() {
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        promptField.stringValue = ""
        onSubmit?(prompt, currentContext)
    }

    @objc private func clearHistoryAction() { onClearHistory?() }

    @objc private func historyItemClicked(_ sender: NSButton) {
        let items = PromptHistoryManager.shared.history
        guard sender.tag < items.count else { return }
        onSubmit?(items[sender.tag], currentContext)
    }

    @objc private func quitAction() { NSApp.terminate(nil) }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            submitAction()
            return true
        }
        return false
    }
}

// MARK: - Permission Row

final class PermissionRow: NSView {
    var onOpenSettings: (() -> Void)?

    private let statusDot = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private var granted = false

    convenience init(title: String, detail: String) {
        self.init(frame: .zero)
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        setup()
    }

    private func setup() {
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 5
        statusDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusDot)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailLabel)

        openButton.title = "Open"
        openButton.bezelStyle = .inline
        openButton.font = .systemFont(ofSize: 11)
        openButton.target = self
        openButton.action = #selector(openAction)
        openButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(openButton)

        NSLayoutConstraint.activate([
            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10),

            titleLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

            openButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            openButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func updateStatus(granted: Bool) {
        self.granted = granted
        statusDot.layer?.backgroundColor = granted ? NSColor.systemGreen.cgColor : NSColor.systemRed.cgColor
        openButton.title = granted ? "Granted" : "Open"
        openButton.isEnabled = !granted
    }

    @objc private func openAction() {
        onOpenSettings?()
    }
}
