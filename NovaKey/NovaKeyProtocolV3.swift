//
//  NovaKeyProtocolV3.swift
//  NovaKey
//

import Foundation
import NovaKeyKEM

enum NovaKeyProtocolV3 {

    enum InnerMsgType: UInt8 {
        case inject = 1
        case approve = 2
        case arm = 3
    }

    enum ProtoError: Error, LocalizedError {
        case missingPairingFields
        case invalidDeviceKeyLength(actual: Int)
        case goBridge(String)
        case emptyFrameReturned

        var errorDescription: String? {
            switch self {
            case .missingPairingFields:
                return "Pairing record is missing required fields"
            case .invalidDeviceKeyLength(let actual):
                return "Device key must be 32 bytes (got \(actual))"
            case .goBridge(let s):
                return "Go bridge failed: \(s)"
            case .emptyFrameReturned:
                return "Go bridge returned an empty frame"
            }
        }
    }

    static func buildFrame(
        pairing: PairingRecord,
        innerType: InnerMsgType,
        payloadUTF8: String
    ) throws -> Data {
        switch innerType {
        case .approve:
            return try buildApproveFrame(pairing: pairing)
        case .inject:
            return try buildInjectFrame(pairing: pairing, secret: payloadUTF8)
        }
    }

    /// "Arm" (user-friendly) currently maps to an approve message.
    /// This avoids changing the Go bridge right now and works with the server's two-man approval gate.
    /// If you later add a dedicated MsgTypeArm, update this to call NovakeykemBuildArmFrame.
    static func buildArmFrame(pairing: PairingRecord, durationMs: Int? = nil) throws -> Data {
        // durationMs intentionally ignored for now (server approve window controls duration).
        return try buildApproveFrame(pairing: pairing)
    }

    static func buildApproveFrame(pairing: PairingRecord) throws -> Data {
        let pairingBlobJSON = try pairing.toProtocolPairingBlobJSON()

        var err: NSError?
        guard let nsData = NovakeykemBuildApproveFrame(pairingBlobJSON, &err) else {
            throw ProtoError.goBridge(err?.localizedDescription ?? "unknown error")
        }

        let data = nsData as Data
        if data.isEmpty { throw ProtoError.emptyFrameReturned }
        return data
    }

    static func buildInjectFrame(pairing: PairingRecord, secret: String) throws -> Data {
        let pairingBlobJSON = try pairing.toProtocolPairingBlobJSON()

        var err: NSError?
        guard let nsData = NovakeykemBuildInjectFrame(pairingBlobJSON, secret, &err) else {
            throw ProtoError.goBridge(err?.localizedDescription ?? "unknown error")
        }

        let data = nsData as Data
        if data.isEmpty { throw ProtoError.emptyFrameReturned }
        return data
    }
}

// MARK: - Pairing blob JSON (must match the daemon)

private extension PairingRecord {

    // Must match daemon pairing blob:
    // { v:3, device_id, device_key_hex, server_addr, server_kyber768_pub }
    func toProtocolPairingBlobJSON() throws -> String {

        struct PairingBlob: Codable {
            let v: Int
            let device_id: String
            let device_key_hex: String
            let server_addr: String
            let server_kyber768_pub: String
        }

        let deviceID = self.deviceID
        let serverAddr = "\(self.serverHost):\(self.serverPort)"
        let serverPubB64 = self.serverPubB64
        let deviceKey = self.deviceKey

        guard !deviceID.isEmpty, !serverAddr.isEmpty, !serverPubB64.isEmpty else {
            throw NovaKeyProtocolV3.ProtoError.missingPairingFields
        }
        guard deviceKey.count == 32 else {
            throw NovaKeyProtocolV3.ProtoError.invalidDeviceKeyLength(actual: deviceKey.count)
        }

        let keyHex = deviceKey.map { String(format: "%02x", $0) }.joined()

        let blob = PairingBlob(
            v: 3, // IMPORTANT: your daemon uses v=3
            device_id: deviceID,
            device_key_hex: keyHex,
            server_addr: serverAddr,
            server_kyber768_pub: serverPubB64
        )

        let data = try JSONEncoder().encode(blob)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NovaKeyProtocolV3.ProtoError.goBridge("JSON encoding failed")
        }
        return json.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
