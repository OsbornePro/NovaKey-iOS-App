//
//  PairingRecord.swift
//  NovaKey
//

import Foundation
import Security

// Expected nvpair blob (what PairingPasteSheet generates / what daemon may export)
struct PairingBlob: Codable {
    let v: Int
    let device_id: String
    let device_key_hex: String
    let server_addr: String          // "host:port"
    let server_kyber768_pub: String  // base64
}

// Stored record (used by NovaKeyProtocolV3 -> Go bridge)
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

    private static func accountKey(host: String, port: Int) -> String {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(h):\(port)"
    }

    // MARK: - Parse nvpair JSON -> PairingRecord

    /// Accepts JSON text that decodes as PairingBlob:
    /// { v:3, device_id, device_key_hex, server_addr, server_kyber768_pub }
    static func parsePairingJSON(_ jsonText: String) throws -> PairingRecord {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw PairingErrors.invalidJSON
        }

        let blob: PairingBlob
        do {
            blob = try JSONDecoder().decode(PairingBlob.self, from: data)
        } catch {
            throw PairingErrors.invalidJSON
        }

        // Version check (you said no legacy)
        guard blob.v == 3 else {
            throw PairingErrors.invalidJSON
        }

        guard let (host, port) = parseHostPort(blob.server_addr) else {
            throw PairingErrors.invalidServerAddr
        }

        guard let keyData = Data(hexString: blob.device_key_hex) else {
            throw PairingErrors.invalidHex
        }
        guard keyData.count == 32 else {
            throw PairingErrors.invalidDeviceKeyLength
        }

        let deviceID = blob.device_id.trimmingCharacters(in: .whitespacesAndNewlines)
        let pub = blob.server_kyber768_pub.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !deviceID.isEmpty, !pub.isEmpty else {
            throw PairingErrors.invalidJSON
        }

        return PairingRecord(
            deviceID: deviceID,
            deviceKey: keyData,
            serverHost: host,
            serverPort: port,
            serverPubB64: pub
        )
    }

    private static func parseHostPort(_ s: String) -> (String, Int)? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let host = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }

        guard let port = Int(parts[1]), port > 0, port <= 65535 else { return nil }
        return (host, port)
    }

    // MARK: - Keychain storage

    /// Primary API: save based on the record's own host/port
    static func save(_ record: PairingRecord) throws {
        let data = try JSONEncoder().encode(record)
        let account = accountKey(host: record.serverHost, port: record.serverPort)

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
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status))
        }
    }

    /// Compatibility overload: keep your existing call sites compiling.
    /// Ignores host/port args and persists under record.serverHost/serverPort.
    static func save(_ record: PairingRecord, host: String, port: Int) throws {
        // Intentionally do NOT re-key storage using the passed host/port:
        // If caller passes listener.host/port but the record differs, that's a mismatch
        // that should be caught earlier (and you already do this check).
        try save(record)
    }

    static func load(host: String, port: Int) -> PairingRecord? {
        let account = accountKey(host: host, port: port)

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

    /// Reset pairing for ONE listener.
    /// - Important: DeviceID is GLOBAL, so default is `resetDeviceID: false`.
    static func resetPairing(host: String, port: Int, resetDeviceID: Bool = false) {
        let account = accountKey(host: host, port: port)
        let del: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(del as CFDictionary)

        if resetDeviceID {
            DeviceIDManager.reset()
        }
    }
}

// MARK: - Stable Device ID (Keychain)
//
// Global device identity for this phone.
// Only reset when the user explicitly chooses "Reset Pairing" (not when deleting a listener).
enum DeviceIDManager {
    private static let service = "com.novakey.deviceid.v1"
    private static let account = "primary"

    static func getOrCreate() -> String {
        if let existing = load(), !existing.isEmpty {
            return existing
        }
        let fresh = "ios-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        save(fresh)
        return fresh
    }

    static func reset() {
        let del: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(del as CFDictionary)
    }

    private static func save(_ s: String) {
        let data = Data(s.utf8)

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
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    private static func load() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
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

