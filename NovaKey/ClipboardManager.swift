//
//  ClipboardManager.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

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
    /// Copies plaintext to clipboard with localOnly (no Universal Clipboard)
    /// and optional expiration (nil when timeout == .never).
    static func copyRawSensitive(_ value: String, timeout: ClipboardTimeout) {
        var options: [UIPasteboard.OptionsKey: Any] = [
            .localOnly: true
        ]

        if let seconds = timeout.seconds {
            options[.expirationDate] = Date().addingTimeInterval(seconds)
        }

        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: value]],
            options: options
        )
    }

    /// Explicitly synchronous.
    static func clearNow() {
        UIPasteboard.general.items = []
    }
}
