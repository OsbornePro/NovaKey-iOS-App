//
//  PairQRDecodeTests.swift
//  NovaKeyTests
//
//  Created by Robert Osborne on 12/26/25.
//

import XCTest
@testable import NovaKey

final class PairQRDecodeTests: XCTestCase {

    func testDecodeV2ValidQR() throws {
        let qr = "novakey://pair?v=2&host=10.0.0.5&port=60769&token=abc123"
        let link = try decodeNovaKeyPairQRLink(qr)

        XCTAssertEqual(link.v, 2)
        XCTAssertEqual(link.host, "10.0.0.5")
        XCTAssertEqual(link.port, 60769)
        XCTAssertEqual(link.token, "abc123")
    }

    func testDecodeRejectsNonNovaKey() {
        let qr = "https://example.com?q=1"
        XCTAssertThrowsError(try decodeNovaKeyPairQRLink(qr)) { err in
            guard let e = err as? PairQRDecodeError else {
                XCTFail("wrong error type")
                return
            }
            XCTAssertEqual(e, .notNovaKeyPair)
        }
    }

    func testDecodeMissingHost() {
        let qr = "novakey://pair?v=2&port=60769&token=abc123"
        XCTAssertThrowsError(try decodeNovaKeyPairQRLink(qr)) { err in
            guard case PairQRDecodeError.missingParam(let p) = err else {
                XCTFail("expected missingParam")
                return
            }
            XCTAssertEqual(p, "host")
        }
    }

    func testDecodeBadPort() {
        let qr = "novakey://pair?v=2&host=10.0.0.5&port=notaport&token=abc123"
        XCTAssertThrowsError(try decodeNovaKeyPairQRLink(qr)) { err in
            guard let e = err as? PairQRDecodeError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e, .badPort)
        }
    }

    func testDecodeMissingToken() {
        let qr = "novakey://pair?v=2&host=10.0.0.5&port=60769"
        XCTAssertThrowsError(try decodeNovaKeyPairQRLink(qr)) { err in
            guard case PairQRDecodeError.missingParam(let p) = err else {
                XCTFail("expected missingParam")
                return
            }
            XCTAssertEqual(p, "token")
        }
    }
}

