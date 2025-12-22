//
//  PairingRecord.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import Foundation
import Security

struct PairingBlob: Codable {
    let v: Int
    let device_id: String
    let device_key_hex: String
    let server_addr: String
    let server_kyber768_pub: String
}

struct PairingRecord: Codable {
    let deviceID: String
    let deviceKey: Data          // 32 bytes
    let serverHost: String
    let serverPort: Int
    let serverPubB64: String     // base64 ML-KEM pubkey
}

enum PairingErrors: Error, LocalizedError {
    case invalidJSON
    case invalidHex
    case invalidServerAddr
    case invalidDeviceKeyLength

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Invalid pairing JSON"
        case .invalidHex: return "Invalid device_key_hex"
        case .invalidServerAddr: return "Invalid server_addr"
        case .invalidDeviceKeyLength: return "device_key_hex must be 32 bytes"
        }
    }
}

enum PairingManager {
    private static let service = "com.novakey.pairing.v3"

    static func parsePairingJSON(_ json: String) throws -> PairingRecord {
        guard let data = json.data(using: .utf8) else { throw PairingErrors.invalidJSON }
        let blob: PairingBlob
        do {
            blob = try JSONDecoder().decode(PairingBlob.self, from: data)
        } catch {
            throw PairingErrors.invalidJSON
        }

        let (host, port) = try parseHostPort(blob.server_addr)

        guard let keyBytes = Data(hexString: blob.device_key_hex) else {
            throw PairingErrors.invalidHex
        }
        guard keyBytes.count == 32 else {
            throw PairingErrors.invalidDeviceKeyLength
        }

        return PairingRecord(
            deviceID: blob.device_id,
            deviceKey: keyBytes,
            serverHost: host,
            serverPort: port,
            serverPubB64: blob.server_kyber768_pub
        )
    }

    static func keychainAccount(host: String, port: Int) -> String {
        "\(host):\(port)"
    }

    static func save(_ record: PairingRecord) throws {
        let account = keychainAccount(host: record.serverHost, port: record.serverPort)
        let data = try JSONEncoder().encode(record)

        // delete existing
        let del: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(del as CFDictionary)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status))
        }
    }

    static func load(host: String, port: Int) -> PairingRecord? {
        let account = keychainAccount(host: host, port: port)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(PairingRecord.self, from: data)
    }

    private static func parseHostPort(_ s: String) throws -> (String, Int) {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else { throw PairingErrors.invalidServerAddr }
        return (String(parts[0]), port)
    }
}

// MARK: - Hex helper
extension Data {
    init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count % 2 == 0 else { return nil }
        var out = Data()
        out.reserveCapacity(s.count / 2)

        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            let byteStr = s[idx..<next]
            guard let b = UInt8(byteStr, radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        self = out
    }
}

func pairingJSON(from qr: PairQR, serverHost: String) throws -> String {
    let blob = PairingBlob(
        v: 3,
        device_id: qr.device_id,
        device_key_hex: qr.device_key_hex,
        server_addr: "\(serverHost):\(qr.listen_port)",
        server_kyber768_pub: qr.server_kyber_pub_b64
    )

    let data = try JSONEncoder().encode(blob)
    return String(decoding: data, as: UTF8.self)
}
