//
//  NovaKeyClient.swift
//  NovaKey
//

import Foundation
import Network

final class NovaKeyClientV3 {

    enum Status: UInt8 {
        case ok = 0x00
        case notArmed = 0x01
        case needsApprove = 0x02
        case notPaired = 0x03
        case badRequest = 0x04
        case badTimestamp = 0x05
        case replay = 0x06
        case rateLimit = 0x07
        case cryptoFail = 0x08

        // server could not inject, but did copy to clipboard successfully
        case okClipboard = 0x09

        case internalError = 0x7F

        var isSuccess: Bool {
            self == .ok || self == .okClipboard
        }
    }

    struct ServerResponse {
        let status: Status
        let message: String
    }

    enum ClientError: Error, LocalizedError {
        case connectFailed(String)
        case sendFailed(String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .connectFailed(let s): return "Connect failed: \(s)"
            case .sendFailed(let s): return "Send failed: \(s)"
            case .badResponse(let s): return "Bad response: \(s)"
            }
        }
    }

    // MARK: - Public API

    func sendInject(secret: String, pairing: PairingRecord) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildFrame(pairing: pairing, innerType: .inject, payloadUTF8: secret)
        return try await sendFrame(frame, host: pairing.serverHost, port: pairing.serverPort)
    }

    func sendApprove(pairing: PairingRecord) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildFrame(pairing: pairing, innerType: .approve, payloadUTF8: "")
        return try await sendFrame(frame, host: pairing.serverHost, port: pairing.serverPort)
    }

    // MARK: - Core

    private func sendFrame(_ frame: Data, host: String, port: Int) async throws -> ServerResponse {
        // The Go bridge already returns: [u16 length BE][payload bytes...]
        guard frame.count >= 2 else {
            throw ClientError.sendFailed("internal: protocol frame too short")
        }

        // Optional sanity check
        let declared = Int(UInt16(frame[0]) << 8 | UInt16(frame[1]))
        let actualPayload = frame.count - 2
        if declared != actualPayload {
            throw ClientError.sendFailed("internal: bad frame length prefix (declared \(declared), actual \(actualPayload))")
        }

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw ClientError.connectFailed("bad port")
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let err):
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: ClientError.connectFailed(err.localizedDescription))
                default:
                    break
                }
            }
            conn.start(queue: .global())
        }

        defer { conn.cancel() }

        // Send exactly what the bridge built (already length-prefixed u16)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: frame, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: ClientError.sendFailed(err.localizedDescription)) }
                else { cont.resume() }
            })
        }

        // Response: [version=3][status][u16 msgLenBE]
        guard let hdr = try await receiveExact(conn, count: 4, timeoutSeconds: 1.5) else {
            throw ClientError.badResponse("no response from server")
        }
        guard hdr.count == 4 else {
            throw ClientError.badResponse("short response header")
        }
        guard hdr[0] == 3 else {
            throw ClientError.badResponse("unexpected response version \(hdr[0])")
        }

        let statusRaw = hdr[1]
        let msgLen = Int(UInt16(hdr[2]) << 8 | UInt16(hdr[3]))

        let msgData = msgLen > 0
            ? (try await receiveExact(conn, count: msgLen, timeoutSeconds: 1.5) ?? Data())
            : Data()

        let msg = String(data: msgData, encoding: .utf8) ?? ""

        guard let status = Status(rawValue: statusRaw) else {
            throw ClientError.badResponse("unknown status \(statusRaw)")
        }

        return ServerResponse(status: status, message: msg)
    }

    // MARK: - Helpers

    private func receiveExact(_ conn: NWConnection, count: Int, timeoutSeconds: Double) async throws -> Data? {
        if count <= 0 { return Data() }

        return try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                var collected = Data()
                while collected.count < count {
                    let chunk = try await self.receiveOnce(conn, maximum: count - collected.count)
                    if chunk.isEmpty { return nil }
                    collected.append(chunk)
                }
                return collected
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }

            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func receiveOnce(_ conn: NWConnection, maximum: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: Swift.max(1, maximum)) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                if isComplete && (data == nil || data?.isEmpty == true) { cont.resume(returning: Data()); return }
                cont.resume(returning: data ?? Data())
            }
        }
    }
}
