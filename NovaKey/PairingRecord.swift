//
//  PairingRecord.swift
//  NovaKey
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
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Invalid pairing JSON"
        case .invalidHex: return "Invalid device_key_hex"
        case .invalidServerAddr: return "Invalid server address"
        case .invalidDeviceKeyLength: return "device_key_hex must be 32 bytes"
        case .unsupportedVersion(let v): return "Unsupported pairing version v=\(v)"
        }
    }
}

enum PairingManager {
    private static let service = "com.novakey.pairing.v3"

    private static func accountKey(host: String, port: Int) -> String {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(h):\(port)"
    }

    // MARK: - Keychain Save/Load

    /// Existing API (kept): saves using record.serverHost/serverPort
    static func save(_ record: PairingRecord) throws {
        try save(record, host: record.serverHost, port: record.serverPort)
    }

    /// Drop-in API (ADDED): call sites in PairingPasteSheet already use this.
    /// Saves under the listener’s host/port key even if the record contains different values.
    static func save(_ record: PairingRecord, host: String, port: Int) throws {
        let data = try JSONEncoder().encode(record)
        let account = accountKey(host: host, port: port)

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

    static func resetPairing(host: String, port: Int) {
        let account = accountKey(host: host, port: port)
        let del: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(del as CFDictionary)
    }

    // MARK: - Parsing nvpair JSON (ADDED)

    /// Drop-in API (ADDED): PairingPasteSheet.saveManualJSON() calls this.
    /// Accepts:
    /// - raw nvpair JSON
    /// - OR "novakey://pair?...": (if a user pastes the QR URL here, we reject with invalidJSON)
    static func parsePairingJSON(_ raw: String) throws -> PairingRecord {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw PairingErrors.invalidJSON }

        // If someone pastes the QR URL into the JSON box, make it fail loudly.
        if s.lowercased().hasPrefix("novakey://") {
            throw PairingErrors.invalidJSON
        }

        guard let data = s.data(using: .utf8) else { throw PairingErrors.invalidJSON }
        let blob: PairingBlob
        do {
            blob = try JSONDecoder().decode(PairingBlob.self, from: data)
        } catch {
            throw PairingErrors.invalidJSON
        }

        // v: allow 3 (your current pairing blob version)
        if blob.v != 3 {
            throw PairingErrors.unsupportedVersion(blob.v)
        }

        let deviceID = blob.device_id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceID.isEmpty else { throw PairingErrors.invalidJSON }

        guard let keyData = Data(hexString: blob.device_key_hex) else {
            throw PairingErrors.invalidHex
        }
        guard keyData.count == 32 else {
            throw PairingErrors.invalidDeviceKeyLength
        }

        let (host, port) = try parseHostPort(blob.server_addr)
        let pub = blob.server_kyber768_pub.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pub.isEmpty else { throw PairingErrors.invalidJSON }

        return PairingRecord(
            deviceID: deviceID,
            deviceKey: keyData,
            serverHost: host,
            serverPort: port,
            serverPubB64: pub
        )
    }

    private static func parseHostPort(_ s: String) throws -> (String, Int) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw PairingErrors.invalidServerAddr }

        let host = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw PairingErrors.invalidServerAddr }

        guard let port = Int(parts[1]), port > 0, port <= 65535 else {
            throw PairingErrors.invalidServerAddr
        }

        return (host, port)
    }
}

// MARK: - Stable Device ID (Keychain)
// The phone keeps a consistent device_id across re-pairs,
// unless the user explicitly resets pairing (UI calls DeviceIDManager.reset()).
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

