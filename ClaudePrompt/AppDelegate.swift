import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, PromptPanelDelegate, StatusBarPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let promptPanel = PromptPanel()
    private let statusPopover = StatusBarPopover()
    private var capturedText: String?
    private let history = PromptHistoryManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("App launched")
        setupStatusItem()
        setupHotkey()
        setupClipboardWatcher()
        promptPanel.promptDelegate = self
        statusPopover.delegate = self

        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        debugLog("Setup complete")
    }

    private func debugLog(_ msg: String) {
        let logFile = NSHomeDirectory() + "/ClaudePrompt/debug.log"
        let line = "\(Date()): \(msg)\n"
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

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = createMenuBarImage()
            button.image?.isTemplate = true
            button.action = #selector(statusBarClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            // Right-click: show quit menu
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // Left-click: toggle popover
            guard let button = statusItem.button else { return }
            statusPopover.toggle(relativeTo: button)
        }
    }

    private func createMenuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: ">_", attributes: attrs)
            let strSize = str.size()
            let origin = NSPoint(
                x: (rect.width - strSize.width) / 2,
                y: (rect.height - strSize.height) / 2
            )
            str.draw(at: origin)
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Clipboard Watcher

    private func setupClipboardWatcher() {
        ClipboardWatcher.shared.onDoubleCopy = { [weak self] text in
            self?.debugLog("Double-copy detected: '\(text.prefix(30))...'")
            self?.capturedText = text
            // Show in popover anchored to status bar
            if let button = self?.statusItem.button {
                self?.statusPopover.showWithContext(text, relativeTo: button)
            }
        }
        ClipboardWatcher.shared.start()
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        HotkeyManager.shared.onTrigger = { [weak self] in
            self?.triggerPrompt()
        }
        HotkeyManager.shared.start()
    }

    private func triggerPrompt() {
        debugLog("triggerPrompt called!")
        HotkeyManager.shared.captureSelectedText { [weak self] text in
            self?.capturedText = text
            self?.promptPanel.show(selectedTextLength: text?.count ?? 0)
        }
    }

    // MARK: - PromptPanelDelegate (for hotkey/services floating panel)

    func promptPanel(_ panel: PromptPanel, didSubmitPrompt prompt: String) {
        panel.dismiss()
        history.add(prompt)
        iTermBridge.send(prompt: prompt, context: capturedText)
        capturedText = nil
    }

    func promptPanelDidCancel(_ panel: PromptPanel) {
        panel.dismiss()
        capturedText = nil
    }

    // MARK: - StatusBarPopoverDelegate

    func statusBarPopover(_ popover: StatusBarPopover, didSubmitPrompt prompt: String, context: String?) {
        history.add(prompt)
        iTermBridge.send(prompt: prompt, context: context)
        capturedText = nil
    }

    func statusBarPopoverDidClearHistory(_ popover: StatusBarPopover) {
        history.clear()
    }

    // MARK: - Services

    @objc func sendToClaudePrompt(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string) else { return }
        capturedText = text
        promptPanel.show(selectedTextLength: text.count)
    }
}
