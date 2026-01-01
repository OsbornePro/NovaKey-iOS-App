import SwiftUI
import UIKit

// MARK: - VoiceOver announcements
enum A11yAnnounce {
    static func say(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - Reduced Motion helper
enum ReduceMotion {
    static func withOptionalAnimation(_ reduceMotion: Bool, _ animation: Animation = .easeInOut(duration: 0.2), _ body: () -> Void) {
        if reduceMotion {
            body()
        } else {
            withAnimation(animation) { body() }
        }
    }
}

// MARK: - Reusable accessibility modifiers
extension View {
    /// For icon-only buttons: makes them VoiceOver + Voice Control friendly.
    func a11yIconButton(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(Text(label))
            .accessibilityHint(hint.map(Text.init) ?? Text(""))
            .accessibilityAddTraits(.isButton)
    }

    /// Combine child views into one accessible element (great for list rows/cards).
    func a11yCombine() -> some View {
        self.accessibilityElement(children: .combine)
    }
}

struct A11yReduceMotion {
    static func withOptionalAnimation(_ reduceMotion: Bool, _ updates: @escaping () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { updates() }
        }
    }
}
