//
//  NovaKeyProtocolV3.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import Foundation
import CryptoKit
import Sodium

// If your gomobile module name differs, chanx  ge this:
import novakeykem

enum NovaKeyProtocolV3 {
    enum InnerMsgType: UInt8 {
        case inject = 1
        case approve = 2
    }

    enum ProtoError: Error, LocalizedError {
        case notPaired
        case kemFailed(String)
        case aeadFailed
        case badLengths

        var errorDescription: String? {
            switch self {
            case .notPaired: return "Not paired with this listener"
            case .kemFailed(let s): return "KEM failed: \(s)"
            case .aeadFailed: return "AEAD encryption failed"
            case .badLengths: return "Protocol length error"
            }
        }
    }

    // Outer framing: [u16 length][payload]
    // Outer payload layout:
    // version=3(u8), outerMsgType=1(u8), idLen(u8), deviceID,
    // kemCtLen(u16BE), kemCt, nonce(24), ciphertext
    static func buildFrame(
        pairing: PairingRecord,
        innerType: InnerMsgType,
        payloadUTF8: String
    ) throws -> Data {

        let deviceIDBytes = Data(pairing.deviceID.utf8)
        guard deviceIDBytes.count <= 255 else { throw ProtoError.badLengths }

        // --- Inner frame (v1) ---
        // [0]=1, [1]=msgType, [2:4]=deviceIDLen(u16BE), [4:8]=payloadLen(u32BE), then deviceID + payload
        let innerPayloadBytes = Data(payloadUTF8.utf8)
        let inner = buildInnerFrame(
            deviceID: deviceIDBytes,
            msgType: innerType,
            payload: innerPayloadBytes
        )

        // Plaintext inside AEAD:
        // [0..7] timestamp u64BE unix seconds
        // [8..] inner frame bytes
        var plaintext = Data()
        plaintext.append(u64be(UInt64(Date().timeIntervalSince1970)))
        plaintext.append(inner)

        // --- KEM: encapsulate to server pubkey ---
        let (kemCt, kemShared) = try encapsulateMLKEM768(serverPubB64: pairing.serverPubB64)

        // --- HKDF-SHA256 derive AEAD key (32 bytes) ---
        let aeadKeyBytes = hkdfKey32(
            kemShared: kemShared,
            deviceKey32: pairing.deviceKey
        )

        // --- Nonce 24 bytes ---
        let nonce = randomBytes(count: 24)

        // --- Build header up through K (AAD) ---
        var header = Data()
        header.append(0x03) // version
        header.append(0x01) // outer msgType fixed to 1
        header.append(UInt8(deviceIDBytes.count))
        header.append(deviceIDBytes)
        header.append(u16be(UInt16(kemCt.count)))
        header.append(kemCt)

        let aad = header // AAD = payload[0:K] (through kemCt)

        // --- AEAD: XChaCha20-Poly1305 Seal ---
        let sodium = Sodium()
        guard let ciphertext = sodium.aead.xchacha20poly1305ietf.encrypt(
            message: plaintext.bytes,
            additionalData: aad.bytes,
            secretKey: aeadKeyBytes.bytes,
            nonce: nonce.bytes
        ) else {
            throw ProtoError.aeadFailed
        }

        // payload = header || nonce || ciphertext
        var payload = Data()
        payload.append(header)
        payload.append(nonce)
        payload.append(Data(ciphertext))

        // Outer framing: u16BE length then payload
        guard payload.count <= 0xFFFF else { throw ProtoError.badLengths }
        var framed = Data()
        framed.append(u16be(UInt16(payload.count)))
        framed.append(payload)

        return framed
    }

    // MARK: - Inner frame builder
    private static func buildInnerFrame(deviceID: Data, msgType: InnerMsgType, payload: Data) -> Data {
        var out = Data()
        out.append(0x01)            // innerVersion
        out.append(msgType.rawValue)

        out.append(u16be(UInt16(deviceID.count)))   // deviceIDLen
        out.append(u32be(UInt32(payload.count)))    // payloadLen

        out.append(deviceID)
        out.append(payload)
        return out
    }

    // MARK: - KEM bridge (gomobile)
    private static func encapsulateMLKEM768(serverPubB64: String) throws -> (kemCt: Data, kemShared: Data) {
        // gomobile exports as top-level function with package prefix.
        // Depending on module naming, this symbol might be `NovakeykemEncapsulate`.
        // Xcode autocomplete will show the exact name.
        let (ctB64, ssB64, errStr) = novakeykem.Encapsulate(serverPubB64)

        if !errStr.isEmpty {
            throw ProtoError.kemFailed(errStr)
        }
        guard
            let ct = Data(base64Encoded: ctB64),
            let ss = Data(base64Encoded: ssB64)
        else {
            throw ProtoError.kemFailed("bad base64 from KEM bridge")
        }
        return (ct, ss)
    }

    // MARK: - HKDF
    private static func hkdfKey32(kemShared: Data, deviceKey32: Data) -> Data {
        let ikm = SymmetricKey(data: kemShared)
        let salt = deviceKey32
        let info = Data("NovaKey v3 AEAD key".utf8)

        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: info,
            outputByteCount: 32
        )

        return derived.withUnsafeBytes { Data($0) }
    }

    // MARK: - Utilities
    private static func randomBytes(count: Int) -> Data {
        var b = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &b)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(b)
    }

    private static func u16be(_ v: UInt16) -> Data {
        var x = v.bigEndian
        return Data(bytes: &x, count: 2)
    }

    private static func u32be(_ v: UInt32) -> Data {
        var x = v.bigEndian
        return Data(bytes: &x, count: 4)
    }

    private static func u64be(_ v: UInt64) -> Data {
        var x = v.bigEndian
        return Data(bytes: &x, count: 8)
    }
}

private extension Data {
    var bytes: [UInt8] { Array(self) }
}
