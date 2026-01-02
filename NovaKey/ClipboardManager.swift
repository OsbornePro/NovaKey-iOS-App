//
//  ClipboardManager.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

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

enum ClipboardTimeout: String, CaseIterable, Identifiable {
    case never
    case s15, s30, s60, s120, s300

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: return "Never"
        case .s15: return "15 seconds"
        case .s30: return "30 seconds"
        case .s60: return "60 seconds"
        case .s120: return "2 minutes"
        case .s300: return "5 minutes"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .never: return nil
        case .s15: return 15
        case .s30: return 30
        case .s60: return 60
        case .s120: return 120
        case .s300: return 300
        }
    }
}

enum ClipboardManager {
    private static let ownedKey = "NovaKeyClipboardOwned"
    private static let ownedChangeCountKey = "NovaKeyClipboardOwnedChangeCount"

    // Injectables for testing (default to real system behavior).
    static var pasteboard: PasteboardProviding = SystemPasteboard()
    static var defaults: UserDefaults = .standard

    /// Copies plaintext to clipboard with localOnly (no Universal Clipboard)
    /// and optional expiration (nil when timeout == .never).
    static func copyRawSensitive(_ value: String, timeout: ClipboardTimeout) {
        var options: [UIPasteboard.OptionsKey: Any] = [
            .localOnly: true
        ]

        if let seconds = timeout.seconds {
            options[.expirationDate] = Date().addingTimeInterval(seconds)
        }

        // Use injectable pasteboard for CI-safe tests.
        pasteboard.setItems(
            [[UTType.plainText.identifier: value]],
            options: options
        )

        // Mark ownership AND remember which clipboard version we wrote.
        defaults.set(true, forKey: ownedKey)
        defaults.set(pasteboard.changeCount, forKey: ownedChangeCountKey)
    }

    /// Clears clipboard ONLY if NovaKey wrote the *current* clipboard contents.
    static func clearNowIfOwnedAndUnchanged() {
        guard defaults.bool(forKey: ownedKey) else { return }

        let ownedChangeCount = defaults.integer(forKey: ownedChangeCountKey)
        let currentChangeCount = pasteboard.changeCount

        // If user copied something else after NovaKey, don't clear it.
        guard ownedChangeCount == currentChangeCount else {
            defaults.set(false, forKey: ownedKey)
            return
        }

        // Clearing items requires the real UIPasteboard API.
        UIPasteboard.general.items = []
        defaults.set(false, forKey: ownedKey)
    }

    /// Optional: call this when app becomes active to drop stale ownership.
    static func discardOwnershipIfClipboardChanged() {
        guard defaults.bool(forKey: ownedKey) else { return }
        let ownedChangeCount = defaults.integer(forKey: ownedChangeCountKey)

        if pasteboard.changeCount != ownedChangeCount {
            defaults.set(false, forKey: ownedKey)
        }
    }

    /// Manual "nuke clipboard now" button can still use this.
    static func clearNow() {
        UIPasteboard.general.items = []
        defaults.set(false, forKey: ownedKey)
    }
}
