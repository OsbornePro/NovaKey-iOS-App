//
//  ClipboardManagerTests.swift
//  NovaKeyTests
//
//  Created by Robert Osborne on 12/26/25.
//

import XCTest
@testable import NovaKey
import UIKit

final class ClipboardManagerTests: XCTestCase {

    func testOwnershipStatePersists() {
        // Note: UIPasteboard may behave differently on simulator vs device.
        // This test focuses on the ownership markers, not actual OS clipboard behavior.

        ClipboardManager.copyRawSensitive("secret", timeout: .s15)

        // After copy, ownership markers should be set.
        let owned = UserDefaults.standard.bool(forKey: "NovaKeyClipboardOwned")
        XCTAssertTrue(owned)
    }

    func testDiscardOwnershipIfClipboardChangedClearsFlag() {
        ClipboardManager.copyRawSensitive("secret", timeout: .s15)

        // Simulate "clipboard changed" by altering stored change count.
        UserDefaults.standard.set(-1, forKey: "NovaKeyClipboardOwnedChangeCount")

        ClipboardManager.discardOwnershipIfClipboardChanged()

        let owned = UserDefaults.standard.bool(forKey: "NovaKeyClipboardOwned")
        XCTAssertFalse(owned)
    }
}
