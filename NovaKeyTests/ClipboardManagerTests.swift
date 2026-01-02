//
//  ClipboardManagerTests.swift
//  NovaKeyTests
//
//  Updated for deterministic CI-safe testing.
//

import XCTest
@testable import NovaKey
import UIKit
import UniformTypeIdentifiers

final class ClipboardManagerTests: XCTestCase {

    // Keep these in sync with ClipboardManager's internal keys.
    private let ownedKey = "NovaKeyClipboardOwned"
    private let ownedChangeCountKey = "NovaKeyClipboardOwnedChangeCount"

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var mockPasteboard: MockPasteboard!

    private var originalDefaults: UserDefaults?
    private var originalPasteboard: PasteboardProviding?

    override func setUp() {
        super.setUp()

        // Unique defaults per test run to prevent cross-test pollution (esp. on CI).
        suiteName = "NovaKeyTests.ClipboardManager.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)

        mockPasteboard = MockPasteboard()

        // Save originals and inject mocks.
        originalDefaults = ClipboardManager.defaults
        originalPasteboard = ClipboardManager.pasteboard

        ClipboardManager.defaults = defaults
        ClipboardManager.pasteboard = mockPasteboard
    }

    override func tearDown() {
        // Restore production dependencies.
        if let originalDefaults { ClipboardManager.defaults = originalDefaults }
        if let originalPasteboard { ClipboardManager.pasteboard = originalPasteboard }

        // Clean up our suite.
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }

        defaults = nil
        mockPasteboard = nil
        suiteName = nil
        originalDefaults = nil
        originalPasteboard = nil

        super.tearDown()
    }

    func testOwnershipStatePersistsAndStoresChangeCount() {
        ClipboardManager.copyRawSensitive("secret", timeout: .s15)

        XCTAssertTrue(defaults.bool(forKey: ownedKey), "Expected NovaKey to mark clipboard as owned after copy.")
        XCTAssertEqual(
            defaults.integer(forKey: ownedChangeCountKey),
            mockPasteboard.changeCount,
            "Expected stored changeCount to match the pasteboard changeCount at time of copy."
        )
    }

    func testDiscardOwnershipIfClipboardChangedClearsFlag() {
        ClipboardManager.copyRawSensitive("secret", timeout: .s15)
        XCTAssertTrue(defaults.bool(forKey: ownedKey))

        // Simulate user copying something else.
        mockPasteboard.simulateExternalChange()

        ClipboardManager.discardOwnershipIfClipboardChanged()

        XCTAssertFalse(defaults.bool(forKey: ownedKey), "Expected ownership to be discarded when clipboard changes.")
    }

    func testClearNowIfOwnedAndUnchangedClearsClipboardAndFlag() {
        ClipboardManager.copyRawSensitive("secret", timeout: .s15)
        XCTAssertTrue(defaults.bool(forKey: ownedKey))
        XCTAssertFalse(mockPasteboard.items.isEmpty, "Expected pasteboard to contain items after copy.")

        ClipboardManager.clearNowIfOwnedAndUnchanged()

        XCTAssertFalse(defaults.bool(forKey: ownedKey), "Expected ownership to be cleared after clearing clipboard.")
        XCTAssertTrue(mockPasteboard.items.isEmpty, "Expected pasteboard items to be cleared when unchanged and owned.")
    }
}

// MARK: - Test double

private final class MockPasteboard: PasteboardProviding {
    private(set) var changeCount: Int = 0
    var items: [[String: Any]] = []

    func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey : Any]) {
        self.items = items
        changeCount += 1
    }

    func simulateExternalChange() {
        // Simulates something outside NovaKey modifying the clipboard.
        changeCount += 1
    }
}
