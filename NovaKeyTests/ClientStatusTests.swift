//
//  ClientStatusTests.swift
//  NovaKeyTests
//

import XCTest
@testable import NovaKey

final class ClientStatusTests: XCTestCase {

    func testStatusHasOkClipboard() throws {
        #if targetEnvironment(simulator) && arch(x86_64)
        throw XCTSkip("Skipping on x86_64 simulator (Intel Mac) due to SIGILL in simulator environment.")
        #endif

        // Ensure the enum recognizes 0x09
        let s = NovaKeyClient.Status(rawValue: 0x09)
        XCTAssertNotNil(s, "Status must support okClipboard (0x09)")
        XCTAssertEqual(s, .okClipboard)
    }
}
