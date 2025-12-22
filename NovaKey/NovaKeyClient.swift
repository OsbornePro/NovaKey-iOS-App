//
//  NovaKeyClient.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import Foundation
import Network

final class NovaKeyClientV3 {
    enum ClientError: Error, LocalizedError {
        case connectFailed
        case sendFailed
        case notPaired

        var errorDescription: String? {
            switch self {
            case .connectFailed: return "Connect failed"
            case .sendFailed: return "Send failed"
            case .notPaired: return "Not paired with this listener"
            }
        }
    }

    func sendInject(secret: String, pairing: PairingRecord) async throws {
        let frame = try NovaKeyProtocolV3.buildFrame(
            pairing: pairing,
            innerType: .inject,
            payloadUTF8: secret
        )
        try await sendFrame(frame, host: pairing.serverHost, port: pairing.serverPort)
    }

    func sendApprove(pairing: PairingRecord) async throws {
        let frame = try NovaKeyProtocolV3.buildFrame(
            pairing: pairing,
            innerType: .approve,
            payloadUTF8: "" // allowed to be empty
        )
        try await sendFrame(frame, host: pairing.serverHost, port: pairing.serverPort)
    }

    private func sendFrame(_ frame: Data, host: String, port: Int) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { throw ClientError.connectFailed }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    cont.resume()
                case .failed(let err):
                    cont.resume(throwing: err)
                default:
                    break
                }
            }
            conn.start(queue: .global())
        }

        defer { conn.cancel() }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: frame, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) }
                else { cont.resume() }
            })
        }

        // Per protocol: server processes then closes.
        // We don’t need to wait for a reply.
    }
}
