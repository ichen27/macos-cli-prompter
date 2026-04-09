import AppKit

final class ClipboardWatcher {
    static let shared = ClipboardWatcher()

    var onDoubleCopy: ((String) -> Void)?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastCopyTime: Date = .distantPast
    private let doubleCopyInterval: TimeInterval = 0.5
    private let pollInterval: TimeInterval = 0.2

    private init() {}

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let now = Date()
        let elapsed = now.timeIntervalSince(lastCopyTime)
        lastCopyTime = now

        if elapsed < doubleCopyInterval {
            // Double-copy detected
            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                onDoubleCopy?(text)
            }
            // Reset so triple-copy doesn't re-trigger
            lastCopyTime = .distantPast
        }
    }
}
