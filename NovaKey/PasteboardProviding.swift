import UIKit

/// Small abstraction so unit tests don't touch the real system clipboard.
protocol PasteboardProviding {
    var changeCount: Int { get }
    func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any])
}

/// Production implementation that uses the system pasteboard.
struct SystemPasteboard: PasteboardProviding {
    var changeCount: Int { UIPasteboard.general.changeCount }

    func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any]) {
        UIPasteboard.general.setItems(items, options: options)
    }
}
