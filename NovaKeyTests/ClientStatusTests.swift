//
//  ClientStatusTests.swift
//  NovaKeyTests
//
//  Created by Robert Osborne on 12/26/25.
//

import XCTest
@testable import NovaKey

final class ClientStatusTests: XCTestCase {

    func testStatusHasOkClipboard() throws {
        // Ensure the enum recognizes 0x09
        let s = NovaKeyClient.Status(rawValue: 0x09)
        XCTAssertNotNil(s, "Status must support okClipboard (0x09)")
        XCTAssertEqual(s, .okClipboard)
    }
}

