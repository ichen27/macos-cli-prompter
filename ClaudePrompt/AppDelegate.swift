import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, PromptPanelDelegate {
    private var statusItem: NSStatusItem!
    private let promptPanel = PromptPanel()
    private var capturedText: String?
    private let history = PromptHistoryManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("App launched")
        setupStatusItem()
        setupHotkey()
        setupClipboardWatcher()
        promptPanel.promptDelegate = self

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
        }

        rebuildMenu()
    }

    private func createMenuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            // Draw ">_" icon
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

    private func rebuildMenu() {
        let menu = NSMenu()

        let recentItems = history.history
        if !recentItems.isEmpty {
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for (index, prompt) in recentItems.prefix(10).enumerated() {
                let truncated = prompt.count > 50 ? String(prompt.prefix(47)) + "..." : prompt
                let item = NSMenuItem(title: truncated, action: #selector(resendPrompt(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())

            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)

            menu.addItem(NSMenuItem.separator())
        }

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Clipboard Watcher

    private func setupClipboardWatcher() {
        ClipboardWatcher.shared.onDoubleCopy = { [weak self] text in
            self?.debugLog("Double-copy detected: '\(text.prefix(30))...'")
            self?.capturedText = text
            self?.promptPanel.show(selectedTextLength: text.count)
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

    // MARK: - PromptPanelDelegate

    func promptPanel(_ panel: PromptPanel, didSubmitPrompt prompt: String) {
        panel.dismiss()
        history.add(prompt)
        rebuildMenu()
        iTermBridge.send(prompt: prompt, context: capturedText)
        capturedText = nil
    }

    func promptPanelDidCancel(_ panel: PromptPanel) {
        panel.dismiss()
        capturedText = nil
    }

    // MARK: - Menu Actions

    @objc private func resendPrompt(_ sender: NSMenuItem) {
        let items = history.history
        guard sender.tag < items.count else { return }
        let prompt = items[sender.tag]

        HotkeyManager.shared.captureSelectedText { [weak self] text in
            self?.history.add(prompt)
            self?.rebuildMenu()
            iTermBridge.send(prompt: prompt, context: text)
        }
    }

    @objc private func clearHistory() {
        history.clear()
        rebuildMenu()
    }

    // MARK: - Services

    @objc func sendToClaudePrompt(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string) else { return }
        capturedText = text
        promptPanel.show(selectedTextLength: text.count)
    }
}
