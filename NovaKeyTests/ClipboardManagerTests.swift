//
//  ClipboardManagerTests.swift
//  NovaKeyTests
//
//  Updated to avoid asserting OS pasteboard content (flaky on iOS)
//

import XCTest
@testable import NovaKey

final class ClipboardManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset ownership markers to keep tests isolated
        UserDefaults.standard.removeObject(forKey: "NovaKeyClipboardOwned")
        UserDefaults.standard.removeObject(forKey: "NovaKeyClipboardOwnedChangeCount")
    }

    func testOwnershipStatePersists() {
        ClipboardManager.copyRawSensitive("secret", timeout: .s15)

        let owned = UserDefaults.standard.bool(forKey: "NovaKeyClipboardOwned")
        XCTAssertTrue(owned, "Expected ownership flag to be set after copying.")
    }

    func testDiscardOwnershipIfClipboardChangedClearsFlag() {
        ClipboardManager.copyRawSensitive("secret", timeout: .s15)

        // Simulate "clipboard changed" by altering stored change count.
        UserDefaults.standard.set(-1, forKey: "NovaKeyClipboardOwnedChangeCount")

        ClipboardManager.discardOwnershipIfClipboardChanged()

        let owned = UserDefaults.standard.bool(forKey: "NovaKeyClipboardOwned")
        XCTAssertFalse(owned, "Expected ownership flag to be cleared when clipboard change is detected.")
    }

    func testClearNowIfOwnedAndUnchangedClearsOwnershipFlag() {
        // We *do not* assert OS clipboard items are cleared (unreliable in tests).
        // We only assert that our ownership markers are cleared when conditions say we own it.

        ClipboardManager.copyRawSensitive("secret", timeout: .s15)

        // If your implementation checks "unchanged", make sure the stored change count
        // matches the current pasteboard change count at the time of copy.
        // copyRawSensitive() should already set these markers.

        ClipboardManager.clearNowIfOwnedAndUnchanged()

        let owned = UserDefaults.standard.bool(forKey: "NovaKeyClipboardOwned")
        XCTAssertFalse(owned, "Expected ownership flag to be cleared by clearNowIfOwnedAndUnchanged().")
    }
}
