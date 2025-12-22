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
    }

    enum ProtoError: Error, LocalizedError {
        case missingPairingFields
        case invalidDeviceKeyLength
        case goBridge(String)

        var errorDescription: String? {
            switch self {
            case .missingPairingFields:
                return "Pairing record is missing required fields"
            case .invalidDeviceKeyLength:
                return "Device key must be 32 bytes"
            case .goBridge(let s):
                return "Go bridge failed: \(s)"
            }
        }
    }

    static func buildFrame(
        pairing: PairingRecord,
        innerType: InnerMsgType,
        payloadUTF8: String
    ) throws -> Data {

        let pairingBlobJSON = try pairing.toProtocolPairingBlobJSON()

        var err: NSError?

        switch innerType {
        case .approve:
            guard let nsData = NovakeykemBuildApproveFrame(pairingBlobJSON, &err) else {
                throw ProtoError.goBridge(err?.localizedDescription ?? "unknown error")
            }
            return nsData as Data

        case .inject:
            guard let nsData = NovakeykemBuildInjectFrame(pairingBlobJSON, payloadUTF8, &err) else {
                throw ProtoError.goBridge(err?.localizedDescription ?? "unknown error")
            }
            return nsData as Data
        }
    }
}

private extension PairingRecord {

    // PROTOCOL.md pairing blob:
    // { v, device_id, device_key_hex, server_addr, server_kyber768_pub }
    func toProtocolPairingBlobJSON() throws -> String {

        struct PairingBlob: Codable {
            let v: Int
            let device_id: String
            let device_key_hex: String
            let server_addr: String
            let server_kyber768_pub: String
        }

        // These names are based on what your PairingPasteSheet uses:
        let deviceID = self.deviceID
        let serverAddr = "\(self.serverHost):\(self.serverPort)"
        let serverPubB64 = self.serverPubB64
        let deviceKey = self.deviceKey

        guard !deviceID.isEmpty, !serverAddr.isEmpty, !serverPubB64.isEmpty else {
            throw NovaKeyProtocolV3.ProtoError.missingPairingFields
        }
        guard deviceKey.count == 32 else {
            throw NovaKeyProtocolV3.ProtoError.invalidDeviceKeyLength
        }

        let keyHex = deviceKey.map { String(format: "%02x", $0) }.joined()

        let blob = PairingBlob(
            v: 1,
            device_id: deviceID,
            device_key_hex: keyHex,
            server_addr: serverAddr,
            server_kyber768_pub: serverPubB64
        )

        let data = try JSONEncoder().encode(blob)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NovaKeyProtocolV3.ProtoError.missingPairingFields
        }
        return json.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
