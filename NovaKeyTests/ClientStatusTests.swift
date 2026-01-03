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
        #if targetEnvironment(simulator) && arch(x86_64)
        try XCTSkipIf(true, "Skipping on x86_64 simulator (Intel Mac) due to SIGILL risk in simulator environment.")
        #endif

        let s = NovaKeyClient.Status(rawValue: 0x09)
        XCTAssertNotNil(s, "Status must support okClipboard (0x09)")
        XCTAssertEqual(s, .okClipboard)
    }
}
