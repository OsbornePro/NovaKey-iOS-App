//
//  PairingManagerTests.swift
//  NovaKeyTests
//
//  Created by Robert Osborne on 12/26/25.
//

import XCTest
@testable import NovaKey

final class PairingManagerTests: XCTestCase {

    func testParseCanonicalPairingBlob() throws {
        // 32-byte device key in hex = 64 hex chars
        let keyHex = String(repeating: "11", count: 32)
        let json = """
        {
          "v": 3,
          "device_id": "ios-1234abcd",
          "device_key_hex": "\(keyHex)",
          "server_addr": "10.0.0.5:60768",
          "server_kyber768_pub": "BASE64PUB=="
        }
        """

        let rec = try PairingManager.parsePairingJSON(json)
        XCTAssertEqual(rec.deviceID, "ios-1234abcd")
        XCTAssertEqual(rec.serverHost, "10.0.0.5")
        XCTAssertEqual(rec.serverPort, 60768)
        XCTAssertEqual(rec.serverPubB64, "BASE64PUB==")
        XCTAssertEqual(rec.deviceKey.count, 32)
    }

    func testParseRejectsBadServerAddr() {
        let keyHex = String(repeating: "11", count: 32)
        let json = """
        {
          "v": 3,
          "device_id": "ios-1234abcd",
          "device_key_hex": "\(keyHex)",
          "server_addr": "10.0.0.5",
          "server_kyber768_pub": "BASE64PUB=="
        }
        """
        XCTAssertThrowsError(try PairingManager.parsePairingJSON(json)) { err in
            guard let e = err as? PairingErrors else { return XCTFail("wrong error type") }
            XCTAssertEqual(e, .invalidServerAddr)
        }
    }

    func testParseRejectsBadHex() {
        let json = """
        {
          "v": 3,
          "device_id": "ios-1234abcd",
          "device_key_hex": "zzzz",
          "server_addr": "10.0.0.5:60768",
          "server_kyber768_pub": "BASE64PUB=="
        }
        """
        XCTAssertThrowsError(try PairingManager.parsePairingJSON(json)) { err in
            guard let e = err as? PairingErrors else { return XCTFail("wrong error type") }
            XCTAssertEqual(e, .invalidHex)
        }
    }

    func testParseRejectsWrongDeviceKeyLength() {
        // 31 bytes
        let keyHex = String(repeating: "11", count: 31)
        let json = """
        {
          "v": 3,
          "device_id": "ios-1234abcd",
          "device_key_hex": "\(keyHex)",
          "server_addr": "10.0.0.5:60768",
          "server_kyber768_pub": "BASE64PUB=="
        }
        """
        XCTAssertThrowsError(try PairingManager.parsePairingJSON(json)) { err in
            guard let e = err as? PairingErrors else { return XCTFail("wrong error type") }
            XCTAssertEqual(e, .invalidDeviceKeyLength)
        }
    }
}

