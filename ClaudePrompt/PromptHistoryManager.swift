import Foundation

final class PromptHistoryManager {
    static let shared = PromptHistoryManager()

    private let key = "promptHistory"
    private let maxItems = 20

    private init() {}

    var history: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func add(_ prompt: String) {
        var items = history
        items.removeAll { $0 == prompt }
        items.insert(prompt, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        UserDefaults.standard.set(items, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
