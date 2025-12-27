//
//  PairQRDecodeTests.swift
//  NovaKeyTests
//
//  Created by Robert Osborne on 12/26/25.
//

import XCTest
@testable import NovaKey

final class PairQRDecodeTests: XCTestCase {

    func testDecodeV3ValidQR() throws {
        let qr = "novakey://pair?v=3&host=10.0.0.5&port=60769&token=abc123"
        let link = try decodeNovaKeyPairQRLink(qr)

        XCTAssertEqual(link.version, 3)
        XCTAssertEqual(link.host, "10.0.0.5")
        XCTAssertEqual(link.port, 60769)
        XCTAssertEqual(link.token, "abc123")
    }

    func testDecodeRejectsNonNovaKey() {
        let qr = "https://example.com?q=1"
        XCTAssertThrowsError(try decodeNovaKeyPairQRLink(qr)) { err in
            guard let e = err as? PairQRDecodeError else {
                return XCTFail("wrong error type: \(type(of: err))")
            }
            XCTAssertEqual(e, .notNovaKeyPair)
        }
    }

    func testDecodeMissingHost() {
        let qr = "novakey://pair?v=3&port=60769&token=abc123"
        XCTAssertThrowsError(try decodeNovaKeyPairQRLink(qr)) { err in
            guard let e = err as? PairQRDecodeError else {
                return XCTFail("wrong error type: \(type(of: err))")
            }
            guard case .missingParam(let p) = e else {
                return XCTFail("expected missingParam, got \(e)")
            }
            XCTAssertEqual(p, "host")
        }
    }

    func testDecodeBadPort() {
        let qr = "novakey://pair?v=3&host=10.0.0.5&port=notaport&token=abc123"
        XCTAssertThrowsError(try decodeNovaKeyPairQRLink(qr)) { err in
            guard let e = err as? PairQRDecodeError else {
                return XCTFail("wrong error type: \(type(of: err))")
            }
            XCTAssertEqual(e, .badPort)
        }
    }

    func testDecodeMissingToken() {
        let qr = "novakey://pair?v=3&host=10.0.0.5&port=60769"
        XCTAssertThrowsError(try decodeNovaKeyPairQRLink(qr)) { err in
            guard let e = err as? PairQRDecodeError else {
                return XCTFail("wrong error type: \(type(of: err))")
            }
            guard case .missingParam(let p) = e else {
                return XCTFail("expected missingParam, got \(e)")
            }
            XCTAssertEqual(p, "token")
        }
    }
}
