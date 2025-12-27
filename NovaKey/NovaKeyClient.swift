//
//  NovaKeyClient.swift
//  NovaKey
//

import Foundation
import Network

// MARK: - Pairing (ML-KEM handshake)

enum NovaKeyPairError: Error, LocalizedError {
    case invalidHost
    case connectFailed(Error?)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost: return "Invalid host"
        case .connectFailed(let e): return "Connect failed: \(e?.localizedDescription ?? "unknown")"
        case .protocolError(let s): return "Protocol error: \(s)"
        }
    }
}

struct PairServerKey: Codable {
    let op: String
    let v: Int
    let kid: String
    let kyber_pub_b64: String
    let fp16_hex: String?      // make optional so decode won’t fail
    let expires_unix: Int64
}

// Swift 6: avoid capturing mutable locals in NWConnection callbacks.
private final class _ConnWaiter: @unchecked Sendable {
    let lock = NSLock()
    var finished = false
    var cont: CheckedContinuation<Void, Error>?
}

final class NovaKeyPairClient {
    private let queue = DispatchQueue(label: "novakey.pair.client")

    func pair(
        host: String,
        port: Int,
        token: String,
        fp16Hex: String? = nil,
        buildRegisterFrame: @escaping (_ serverKey: PairServerKey, _ tokenRawURLB64: String) throws -> Data,
        handleAck: @escaping (_ serverKey: PairServerKey, _ ack: Data, _ tokenRawURLB64: String) throws -> Void
    ) async throws {

        let hostTrimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostTrimmed.isEmpty else { throw NovaKeyPairError.invalidHost }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { throw NovaKeyPairError.invalidHost }

        let conn = NWConnection(host: NWEndpoint.Host(hostTrimmed), port: nwPort, using: .tcp)
        defer { conn.cancel() }

        try await connect(conn)

        // 1) Route line (router.go reads this)
        try await send(conn, Data("NOVAK/1 /pair\n".utf8))

        // 2) Hello JSON line (pairing_proto.go reads this)
        var helloObj: [String: Any] = ["op": "hello", "v": 1, "token": token]
        // daemon ignores unknown fields, so including fp is safe (but not required)
        if let fp16Hex, !fp16Hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            helloObj["fp"] = fp16Hex
        }
        try await send(conn, try jsonLine(helloObj))

        // 3) server_key line
        let serverKeyLine = try await readLine(conn, maxBytes: 16 * 1024)
        let serverKey = try decodeServerKey(serverKeyLine)

        // 4) Build register frame (binary) and send it as FINAL (half-close write side)
        // Your Go KEM bridge expects tokenRawURLB64 = the base64url token string from QR.
        let tokenRawURLB64 = token
        let registerFrame = try buildRegisterFrame(serverKey, tokenRawURLB64)

        // *** CRITICAL ***
        // Daemon reads ciphertext with io.ReadAll() until EOF,
        // so we MUST signal end-of-stream after sending the register frame.
        try await sendFinal(conn, registerFrame)

        // 5) Read ack (daemon writes: [24-byte nonce][ciphertext])
        let ack = try await readToCloseOrIdle(conn, maxBytes: 256 * 1024)
        guard ack.count >= 24 + 16 else {
            throw NovaKeyPairError.protocolError("ack too short: \(ack.count)")
        }

        try handleAck(serverKey, ack, tokenRawURLB64)
    }

    // MARK: - NW helpers (Swift 6 safe)

    private func connect(_ conn: NWConnection) async throws {
        let waiter = _ConnWaiter()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            waiter.lock.lock()
            waiter.cont = cont
            waiter.lock.unlock()

            conn.stateUpdateHandler = { st in
                waiter.lock.lock()
                defer { waiter.lock.unlock() }
                guard waiter.finished == false else { return }

                switch st {
                case .ready:
                    waiter.finished = true
                    waiter.cont?.resume(returning: ())
                    waiter.cont = nil
                case .failed(let e):
                    waiter.finished = true
                    waiter.cont?.resume(throwing: NovaKeyPairError.connectFailed(e))
                    waiter.cont = nil
                default:
                    break
                }
            }

            conn.start(queue: self.queue)
        }
    }

    private func send(_ conn: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) }
                else { cont.resume(returning: ()) }
            })
        }
    }

    // Send final payload and mark stream complete (half-close write side).
    private func sendFinal(_ conn: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) }
                else { cont.resume(returning: ()) }
            })
        }
    }

    private func receive(_ conn: NWConnection, min: Int, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: min, maximumLength: max) { data, _, _, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: data ?? Data())
            }
        }
    }

    private func readLine(_ conn: NWConnection, maxBytes: Int) async throws -> Data {
        var buffer = Data()
        while buffer.count < maxBytes {
            let chunk = try await receive(conn, min: 1, max: 2048)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if buffer.contains(0x0A) { break } // '\n'
        }
        guard let nl = buffer.firstIndex(of: 0x0A) else {
            throw NovaKeyPairError.protocolError("no newline in server_key")
        }
        return buffer.prefix(upTo: buffer.index(after: nl))
    }

    private func readToCloseOrIdle(_ conn: NWConnection, maxBytes: Int) async throws -> Data {
        var out = Data()
        var idleReads = 0

        while out.count < maxBytes {
            let chunk = try await receive(conn, min: 1, max: 4096)
            if chunk.isEmpty {
                idleReads += 1
                if idleReads >= 2 { break }
            } else {
                idleReads = 0
                out.append(chunk)
            }
        }
        return out
    }

    // MARK: - JSON helpers

    private func jsonLine(_ obj: [String: Any]) throws -> Data {
        let b = try JSONSerialization.data(withJSONObject: obj, options: [])
        var out = Data()
        out.append(b)
        out.append(0x0A)
        return out
    }

    private func decodeServerKey(_ line: Data) throws -> PairServerKey {
        let trimmed = line.trimmingTrailingNewlines()
        guard let sk = try? JSONDecoder().decode(PairServerKey.self, from: trimmed),
              sk.op == "server_key", sk.v == 1 else {
            throw NovaKeyPairError.protocolError("bad server_key response: \(String(decoding: trimmed, as: UTF8.self))")
        }
        return sk
    }
}

// MARK: - Send client (/v3)

final class NovaKeyClient {
    private let queue = DispatchQueue(label: "novakey.send.client")
    private let routeLine = "NOVAK/1 /v3\n"

    // Your UI expects these:
    enum Status: UInt8, Codable, CustomStringConvertible {
        case ok = 0x00
        case okClipboard = 0x01

        case badRequest = 0x10
        case notPaired  = 0x11
        case cryptoFail = 0x12

        case notArmed     = 0x20
        case needsApprove = 0x21

        case badTimestamp = 0x30
        case replay       = 0x31

        case rateLimit    = 0x40
        case internalError = 0x50

        case unknown = 0xFF

        var isSuccess: Bool { self == .ok || self == .okClipboard }

        var description: String {
            switch self {
            case .ok: return "ok"
            case .okClipboard: return "okClipboard"
            case .badRequest: return "badRequest"
            case .notPaired: return "notPaired"
            case .cryptoFail: return "cryptoFail"
            case .notArmed: return "notArmed"
            case .needsApprove: return "needsApprove"
            case .badTimestamp: return "badTimestamp"
            case .replay: return "replay"
            case .rateLimit: return "rateLimit"
            case .internalError: return "internalError"
            case .unknown: return "unknown"
            }
        }

        static func from(raw: UInt8) -> Status {
            Status(rawValue: raw) ?? .unknown
        }
    }

    struct ServerResponse {
        let status: Status
        let message: String
    }

    enum ClientError: Error, LocalizedError {
        case invalidHost
        case connectFailed(Error?)
        case badReply(String)

        var errorDescription: String? {
            switch self {
            case .invalidHost: return "Invalid host"
            case .connectFailed(let e): return "Connect failed: \(e?.localizedDescription ?? "unknown")"
            case .badReply(let s): return "Bad reply: \(s)"
            }
        }
    }

    // MARK: Public API used by ContentView

    func sendApprove(pairing: PairingRecord) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildApproveFrame(pairing: pairing)
        let data = try await sendRaw(frame: frame, host: pairing.serverHost, port: pairing.serverPort)
        return try parseServerResponse(data)
    }

    func sendInject(secret: String, pairing: PairingRecord) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildInjectFrame(pairing: pairing, secret: secret)
        let data = try await sendRaw(frame: frame, host: pairing.serverHost, port: pairing.serverPort)
        return try parseServerResponse(data)
    }

    // MARK: Raw transport

    func sendRaw(frame: Data, host: String, port: Int) async throws -> Data {
        let hostTrimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostTrimmed.isEmpty else { throw ClientError.invalidHost }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { throw ClientError.invalidHost }

        let conn = NWConnection(host: NWEndpoint.Host(hostTrimmed), port: nwPort, using: .tcp)
        defer { conn.cancel() }

        try await connect(conn)
        try await send(conn, Data(routeLine.utf8))
        try await send(conn, frame)
        return try await readToCloseOrIdle(conn, maxBytes: 256 * 1024)
    }

    // MARK: Swift 6 safe connect/send/recv

    private func connect(_ conn: NWConnection) async throws {
        let waiter = _ConnWaiter()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            waiter.lock.lock()
            waiter.cont = cont
            waiter.lock.unlock()

            conn.stateUpdateHandler = { st in
                waiter.lock.lock()
                defer { waiter.lock.unlock() }

                guard waiter.finished == false else { return }

                switch st {
                case .ready:
                    waiter.finished = true
                    waiter.cont?.resume(returning: ())
                    waiter.cont = nil
                case .failed(let e):
                    waiter.finished = true
                    waiter.cont?.resume(throwing: ClientError.connectFailed(e))
                    waiter.cont = nil
                default:
                    break
                }
            }

            conn.start(queue: self.queue)
        }
    }

    private func send(_ conn: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) }
                else { cont.resume(returning: ()) }
            })
        }
    }

    private func receive(_ conn: NWConnection, min: Int, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: min, maximumLength: max) { data, _, _, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: data ?? Data())
            }
        }
    }

    private func readToCloseOrIdle(_ conn: NWConnection, maxBytes: Int) async throws -> Data {
        var out = Data()
        var idleReads = 0

        while out.count < maxBytes {
            let chunk = try await receive(conn, min: 1, max: 4096)
            if chunk.isEmpty {
                idleReads += 1
                if idleReads >= 2 { break }
            } else {
                idleReads = 0
                out.append(chunk)
                // v3 daemon replies are newline terminated JSON
                if out.contains(0x0A) { break }
            }
        }
        return out
    }

    // MARK: Reply parsing

    private func parseServerResponse(_ data: Data) throws -> ServerResponse {
        let trimmed = data.trimmingTrailingNewlines()
        guard !trimmed.isEmpty else {
            throw ClientError.badReply("empty response")
        }

        // Expected daemon response: JSON line.
        // We support a few shapes so you can evolve server without breaking iOS.

        // Shape A: { "status": 0, "message": "..." }
        struct RespA: Decodable {
            let status: UInt8
            let message: String?
        }
        if let a = try? JSONDecoder().decode(RespA.self, from: trimmed) {
            return ServerResponse(status: Status.from(raw: a.status), message: a.message ?? "")
        }

        // Shape B: { "ok": true/false, "error": "..." }
        struct RespB: Decodable {
            let ok: Bool
            let error: String?
        }
        if let b = try? JSONDecoder().decode(RespB.self, from: trimmed) {
            return ServerResponse(status: b.ok ? .ok : .badRequest, message: b.error ?? "")
        }

        // Fallback: treat as plaintext
        let s = String(decoding: trimmed, as: UTF8.self)
        return ServerResponse(status: .unknown, message: s)
    }
}

private extension Data {
    func trimmingTrailingNewlines() -> Data {
        var d = self
        while let last = d.last, last == 0x0A || last == 0x0D { d.removeLast() }
        return d
    }
}
