//
//  NovaKeyClient.swift
//  NovaKey
//
//  DROP-IN REPLACEMENT (compiles with your current ServerResponse fields)
//
//  Fixes:
//  1) No duplicate readLine()
//  2) Deterministic daemon reply read: reads ONE newline-terminated JSON line
//  3) parseServerResponse returns ALL required fields:
//        status, message, stage, reason, reqID
//
//  Notes:
//  - Pairing (/pair) still uses sendFinal (EOF) because pairing handler reads until EOF.
//  - Send (/msg) uses normal send (no half-close) and reads a single JSON line.
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
    let fp16_hex: String?
    let expires_unix: Int64
}

// These MUST match your daemon JSON reply schema in reply.go
private struct DaemonReply: Decodable {
    let v: Int
    let status: UInt8
    let stage: Stage
    let reason: Reason
    let msg: String
    let ts_unix: Int64
    let req_id: UInt64
}

enum Stage: String, Decodable {
    case msg, inject, approve, arm, disarm
}

enum Reason: String, Decodable {
    case ok
    case clipboard_fallback
    case inject_unavailable_wayland
    case not_armed
    case needs_approve
    case not_paired
    case bad_request
    case bad_timestamp
    case replay
    case rate_limit
    case crypto_fail
    case internal_error
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

        // 1) Route line
        try await send(conn, Data("NOVAK/1 /pair\n".utf8))

        // 2) Hello JSON line (pairing protocol version stays v=1)
        var helloObj: [String: Any] = ["op": "hello", "v": 1, "token": token]
        if let fp16Hex, !fp16Hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            helloObj["fp"] = fp16Hex
        }
        try await send(conn, try jsonLine(helloObj))

        // 3) server_key line
        let serverKeyLine = try await readLineExpectNewline(
            conn,
            maxBytes: 16 * 1024,
            errMsgIfMissingNL: "no newline in server_key"
        )
        let serverKey = try decodeServerKey(serverKeyLine)

        // 4) Build register frame (binary) and send as FINAL (half-close write side).
        // Pairing handler reads until EOF.
        let tokenRawURLB64 = token
        let registerFrame = try buildRegisterFrame(serverKey, tokenRawURLB64)
        try await sendFinal(conn, registerFrame)

        // 5) Read ack (daemon writes: [24-byte nonce][ciphertext])
        let ack = try await withTimeout(5.0) { [self] in
            try await self.readAck(conn, maxBytes: 256 * 1024)
        }
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
            conn.send(
                content: data,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { err in
                    if let err { cont.resume(throwing: err) }
                    else { cont.resume(returning: ()) }
                }
            )
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

    // Read up to and INCLUDING newline. Throws if newline never appears.
    private func readLineExpectNewline(_ conn: NWConnection, maxBytes: Int, errMsgIfMissingNL: String) async throws -> Data {
        var buffer = Data()
        while buffer.count < maxBytes {
            let chunk = try await receive(conn, min: 1, max: 2048)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if buffer.contains(0x0A) { break } // '\n'
        }
        guard let nl = buffer.firstIndex(of: 0x0A) else {
            throw NovaKeyPairError.protocolError(errMsgIfMissingNL)
        }
        return buffer.prefix(upTo: buffer.index(after: nl))
    }

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

    private func readExact(_ conn: NWConnection, count: Int, maxChunk: Int = 4096) async throws -> Data {
        var out = Data()
        out.reserveCapacity(count)

        while out.count < count {
            let need = count - out.count
            let chunk = try await receive(conn, min: 1, max: min(maxChunk, need))
            if chunk.isEmpty {
                throw NovaKeyPairError.protocolError("connection closed while reading (got \(out.count)/\(count))")
            }
            out.append(chunk)
        }
        return out
    }

    private func readAck(_ conn: NWConnection, maxBytes: Int) async throws -> Data {
        // 1) nonce (exactly 24 bytes)
        let nonce = try await readExact(conn, count: 24)

        // 2) read ONE chunk of ciphertext (should contain the whole ack)
        let ct = try await receive(conn, min: 1, max: min(4096, maxBytes - 24))
        if ct.isEmpty {
            throw NovaKeyPairError.protocolError("empty ack ciphertext")
        }

        let ack = nonce + ct
        guard ack.count >= 24 + 16 else {
            throw NovaKeyPairError.protocolError("ack too short: \(ack.count)")
        }
        return ack
    }

    private func withTimeout<T>(_ seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NovaKeyPairError.protocolError("timeout waiting for server response")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Send client (/msg)

final class NovaKeyClient {
    private let queue = DispatchQueue(label: "novakey.send.client")
    private let routeLine = "NOVAK/1 /msg\n"

    enum Status: UInt8, Codable, CustomStringConvertible {
        case ok            = 0x00
        case notArmed      = 0x01
        case needsApprove  = 0x02
        case notPaired     = 0x03
        case badRequest    = 0x04
        case badTimestamp  = 0x05
        case replay        = 0x06
        case rateLimit     = 0x07
        case cryptoFail    = 0x08
        case okClipboard   = 0x09
        case internalError = 0x7F
        case unknown       = 0xFF

        var isSuccess: Bool { self == .ok || self == .okClipboard }

        static func from(raw: UInt8) -> Status {
            Status(rawValue: raw) ?? .unknown
        }

        var description: String { "\(self)" }
    }

    struct ServerResponse {
        let status: NovaKeyClient.Status
        let message: String
        let stage: Stage
        let reason: Reason
        let reqID: UInt64
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

    // MARK: Public API

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

    func sendArm(pairing: PairingRecord, durationMs: Int? = nil) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildArmFrame(pairing: pairing, durationMs: durationMs)
        let data = try await sendRaw(frame: frame, host: pairing.serverHost, port: pairing.serverPort)
        return try parseServerResponse(data)
    }

    func sendDisarm(pairing: PairingRecord) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildDisarmFrame(pairing: pairing)
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

        // Deterministic: daemon replies with ONE newline-terminated JSON line
        return try await readLine(conn, maxBytes: 256 * 1024)
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

    // Read up to newline OR close.
    private func readLine(_ conn: NWConnection, maxBytes: Int) async throws -> Data {
        var buffer = Data()
        while buffer.count < maxBytes {
            let chunk = try await receive(conn, min: 1, max: 2048)
            if chunk.isEmpty { break } // peer closed
            buffer.append(chunk)
            if buffer.contains(0x0A) { break } // '\n'
        }
        return buffer
    }

    // MARK: Reply parsing (FIXED: fills stage/reason/reqID)

    private func parseServerResponse(_ data: Data) throws -> ServerResponse {
        let trimmed = data.trimmingTrailingNewlines()
        guard !trimmed.isEmpty else { throw ClientError.badReply("empty response") }

        do {
            let d = try JSONDecoder().decode(DaemonReply.self, from: trimmed)
            return ServerResponse(
                status: Status.from(raw: d.status),
                message: d.msg,
                stage: d.stage,
                reason: d.reason,
                reqID: d.req_id
            )
        } catch {
            let raw = String(decoding: trimmed, as: UTF8.self)
            throw ClientError.badReply("decode failed: \(error.localizedDescription) raw=\(raw)")
        }
    }
}

private extension Data {
    func trimmingTrailingNewlines() -> Data {
        var d = self
        while let last = d.last, last == 0x0A || last == 0x0D { d.removeLast() }
        return d
    }
}
