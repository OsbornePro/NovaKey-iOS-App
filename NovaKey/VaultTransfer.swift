//
//  VaultTransfer.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import Foundation
import SwiftData
import CryptoKit
import LocalAuthentication

// MARK: - Options

enum VaultProtection: String, CaseIterable, Identifiable, Codable {
    case none
    case password

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .password: return "Password"
        }
    }
}

enum VaultCipher: String, CaseIterable, Identifiable, Codable {
    case none
    case aesGcm256
    case chachaPoly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .aesGcm256: return "AES-256-GCM"
        case .chachaPoly: return "ChaCha20-Poly1305"
        }
    }
}

// MARK: - Errors

enum VaultTransferError: LocalizedError {
    case passwordRequired
    case invalidFormat
    case unsupported
    case decryptFailed

    var errorDescription: String? {
        switch self {
        case .passwordRequired: return "This vault export is password-protected. Please enter the password."
        case .invalidFormat: return "Invalid vault file format."
        case .unsupported: return "Unsupported vault format or options."
        case .decryptFailed: return "Could not decrypt vault (wrong password or corrupted file)."
        }
    }
}

// MARK: - File formats

struct VaultSecretRecord: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let lastUsedAt: Date?
    let secret: String
}

struct VaultPayload: Codable {
    let version: Int
    let exportedAt: Date
    let secrets: [VaultSecretRecord]
}

struct VaultEnvelope: Codable {
    let version: Int
    let protection: VaultProtection
    let cipher: VaultCipher

    /// random salt for KDF (base64). nil if no password.
    let saltB64: String?

    /// nonce for cipher (base64). nil if no encryption.
    let nonceB64: String?

    /// ciphertext (base64). For unencrypted, this is just the UTF8 vault JSON.
    let dataB64: String
}

// MARK: - Transfer

enum VaultTransfer {

    // Export: build payload JSON; optionally encrypt into envelope.
    static func exportVault(
        modelContext: ModelContext,
        protection: VaultProtection,
        cipher: VaultCipher,
        password: String?,
        requireFreshBiometric: Bool
    ) throws -> Data {

        // Pull all SecretItem rows
        let all = try modelContext.fetch(FetchDescriptor<SecretItem>())

        // Use ONE LAContext for the entire export run.
        let context = LAContext()
        context.localizedReason = "Export secrets"

        // If requireFreshBiometric: always prompt (reuse = 0).
        // Else: allow short reuse so export only prompts once.
        context.touchIDAuthenticationAllowableReuseDuration = requireFreshBiometric ? 0 : 10

        // Read secrets from Keychain for export
        let records: [VaultSecretRecord] = try all.map { item in
            // Per-item prompt helps some UIs; the context reuse duration controls whether it re-prompts.
            context.localizedReason = "Export \(item.name)"

            let s = try KeyChainVault.shared.readSecret(for: item.id, using: context)
            return VaultSecretRecord(
                id: item.id,
                name: item.name,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                lastUsedAt: item.lastUsedAt,
                secret: s
            )
        }

        let payload = VaultPayload(version: 1, exportedAt: .now, secrets: records)
        let payloadData = try JSONEncoder().encode(payload)

        // No protection -> store plaintext JSON inside envelope
        if protection == .none || cipher == .none {
            let env = VaultEnvelope(
                version: 1,
                protection: .none,
                cipher: .none,
                saltB64: nil,
                nonceB64: nil,
                dataB64: payloadData.base64EncodedString()
            )
            return try JSONEncoder().encode(env)
        }

        // Password required
        guard protection == .password else { throw VaultTransferError.unsupported }
        guard let password, !password.isEmpty else { throw VaultTransferError.passwordRequired }

        let salt = randomBytes(count: 16)
        let key = deriveKey(password: password, salt: salt, length: 32)

        switch cipher {
        case .aesGcm256:
            let sealed = try AES.GCM.seal(payloadData, using: key)
            guard let combined = sealed.combined else { throw VaultTransferError.invalidFormat }
            let env = VaultEnvelope(
                version: 1,
                protection: .password,
                cipher: .aesGcm256,
                saltB64: salt.base64EncodedString(),
                nonceB64: nil, // included in combined
                dataB64: combined.base64EncodedString()
            )
            return try JSONEncoder().encode(env)

        case .chachaPoly:
            let sealed = try ChaChaPoly.seal(payloadData, using: key)
            let combined = sealed.combined
            let env = VaultEnvelope(
                version: 1,
                protection: .password,
                cipher: .chachaPoly,
                saltB64: salt.base64EncodedString(),
                nonceB64: nil, // included in combined
                dataB64: combined.base64EncodedString()
            )
            return try JSONEncoder().encode(env)

        case .none:
            throw VaultTransferError.unsupported
        }
    }

    // Import: decode envelope, decrypt if needed, return payload.
    static func importVault(data: Data, password: String?) throws -> VaultPayload {
        let env: VaultEnvelope
        do {
            env = try JSONDecoder().decode(VaultEnvelope.self, from: data)
        } catch {
            throw VaultTransferError.invalidFormat
        }

        guard env.version == 1 else { throw VaultTransferError.unsupported }

        // Unencrypted
        if env.protection == .none || env.cipher == .none {
            guard let raw = Data(base64Encoded: env.dataB64) else { throw VaultTransferError.invalidFormat }
            return try JSONDecoder().decode(VaultPayload.self, from: raw)
        }

        // Password-protected
        guard env.protection == .password else { throw VaultTransferError.unsupported }
        guard let password, !password.isEmpty else { throw VaultTransferError.passwordRequired }

        guard let saltB64 = env.saltB64,
              let salt = Data(base64Encoded: saltB64),
              let ct = Data(base64Encoded: env.dataB64)
        else { throw VaultTransferError.invalidFormat }

        let key = deriveKey(password: password, salt: salt, length: 32)

        do {
            let plaintext: Data
            switch env.cipher {
            case .aesGcm256:
                let box = try AES.GCM.SealedBox(combined: ct)
                plaintext = try AES.GCM.open(box, using: key)

            case .chachaPoly:
                let box = try ChaChaPoly.SealedBox(combined: ct)
                plaintext = try ChaChaPoly.open(box, using: key)

            case .none:
                throw VaultTransferError.unsupported
            }

            return try JSONDecoder().decode(VaultPayload.self, from: plaintext)
        } catch {
            throw VaultTransferError.decryptFailed
        }
    }

    // MARK: - Helpers

    private static func randomBytes(count: Int) -> Data {
        var b = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &b)
        return Data(b)
    }

    /// HKDF-SHA256: password -> SymmetricKey; salt random; info constant; output 32 bytes.
    private static func deriveKey(password: String, salt: Data, length: Int) -> SymmetricKey {
        let ikm = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data("NovaKeyVault".utf8),
            outputByteCount: length
        )
    }
}
