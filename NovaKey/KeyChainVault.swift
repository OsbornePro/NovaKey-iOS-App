//
//  KeyChainVault.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import Foundation
import Security
import LocalAuthentication

enum VaultError: Error {
    case keychain(OSStatus)
    case invalidData
}

final class KeyChainVault {
    static let shared = KeyChainVault()
    private init() {}

    private func key(for id: UUID) -> String {
        "com.novakey.vault.secret.\(id.uuidString)"
    }

    private func makeAccessControl() throws -> SecAccessControl {
        var err: Unmanaged<CFError>?

        // Strongest: invalidates if biometric set changes
        if let ac = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.biometryCurrentSet],
            &err
        ) {
            return ac
        }

        // Fallback: user presence (FaceID/TouchID/passcode)
        err = nil
        if let ac = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence],
            &err
        ) {
            return ac
        }

        throw VaultError.invalidData
    }

    func save(secret: String, for id: UUID) throws {
        let secretData = Data(secret.utf8)
        let account = key(for: id)
        let access = try makeAccessControl()

        // Upsert
        let delQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(delQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: secretData,
            kSecAttrAccessControl as String: access
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }

    /// Modern API: lets you force Face ID every time (reuse window = 0).
    func readSecret(for id: UUID, prompt: String, requireFreshBiometric: Bool) throws -> String {
        let account = key(for: id)

        // Use one LAContext so the system can reuse auth during export
        let context = LAContext()
        context.localizedReason = prompt

        // If user wants Face ID every single time:
        if requireFreshBiometric {
            context.touchIDAuthenticationAllowableReuseDuration = 0
        } else {
            // Small reuse window so export prompts once
            context.touchIDAuthenticationAllowableReuseDuration = 10
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        guard let data = item as? Data else { throw VaultError.invalidData }
        guard let s = String(data: data, encoding: .utf8) else { throw VaultError.invalidData }
        return s
    }

    /// Compatibility overload so old call sites compile.
    /// Uses `requireFreshBiometric = true` by default.
    func readSecret(for id: UUID, prompt: String) throws -> String {
        try readSecret(for: id, prompt: prompt, requireFreshBiometric: true)
    }

    /// Used by export: reuse the SAME context across many reads -> one prompt.
    func readSecret(for id: UUID, using context: LAContext) throws -> String {
        let account = key(for: id)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        guard let data = item as? Data else { throw VaultError.invalidData }
        guard let s = String(data: data, encoding: .utf8) else { throw VaultError.invalidData }
        return s
    }

    func deleteSecret(for id: UUID) {
        let account = key(for: id)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
