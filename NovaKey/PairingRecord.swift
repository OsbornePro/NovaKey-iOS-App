//
//  PairingRecord.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import Foundation
import Security

// Expected nvpair blob (what PairingPasteSheet generates via makePairingJSON)
struct PairingBlob: Codable {
    let v: Int
    let device_id: String
    let device_key_hex: String
    let server_addr: String          // "host:port"
    let server_kyber768_pub: String  // base64
}

// Stored record
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
        case .invalidServerAddr: return "Invalid server address"
        case .invalidDeviceKeyLength: return "device_key_hex must be 32 bytes"
        }
    }
}

enum PairingManager {
    private static let service = "com.novakey.pairing.v3"

    /// Accepts either:
    /// 1) nvpair blob:
    ///    { v, device_id, device_key_hex, server_addr, server_kyber768_pub }
    ///
    /// 2) alternate manual blob:
    ///    { server_url, device_id, device_key_hex, kyber768_public }  (or server_kyber768_pub)
    static func parsePairingJSON(_ json: String) throws -> PairingRecord {
        guard let data = json.data(using: .utf8) else { throw PairingErrors.invalidJSON }

        // --- Format 1: canonical nvpair blob ---
        if let blob = try? JSONDecoder().decode(PairingBlob.self, from: data) {
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

        // --- Format 2: manual blob (server_url + key + pub) ---
        struct AltBlob: Decodable {
            let server_url: String
            let device_id: String
            let device_key_hex: String
            let kyber768_public: String?
            let server_kyber768_pub: String?
        }

        guard let alt = try? JSONDecoder().decode(AltBlob.self, from: data) else {
            throw PairingErrors.invalidJSON
        }

        guard let url = URL(string: alt.server_url),
              let host = url.host,
              let port = url.port else {
            throw PairingErrors.invalidServerAddr
        }

        guard let keyBytes = Data(hexString: alt.device_key_hex) else {
            throw PairingErrors.invalidHex
        }
        guard keyBytes.count == 32 else {
            throw PairingErrors.invalidDeviceKeyLength
        }

        let pub = alt.server_kyber768_pub ?? alt.kyber768_public ?? ""
        guard !pub.isEmpty else { throw PairingErrors.invalidJSON }

        return PairingRecord(
            deviceID: alt.device_id,
            deviceKey: keyBytes,
            serverHost: host,
            serverPort: port,
            serverPubB64: pub
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
        // Accept "host:port"
        let parts = s.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else { throw PairingErrors.invalidServerAddr }
        let host = String(parts[0])
        guard !host.isEmpty, port > 0 else { throw PairingErrors.invalidServerAddr }
        return (host, port)
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

