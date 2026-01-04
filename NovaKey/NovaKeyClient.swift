//
//  NovaKeyClient.swift
//  NovaKey
//
//  Notes:
//  - Pairing (/pair) still uses sendFinal (EOF) because pairing handler reads until EOF.
//  - Send (/msg) uses normal send (no half-close) and reads a single JSON line.
//  - Forward-compatible reply parsing:
//      * Primary schema: DaemonReply (v/status/stage/reason/msg/ts_unix/req_id)
//      * Alternate schema: AltReply (ok/status/error/reason/message/clipboard_fallback/...)
//  - Never crashes on unknown/changed server responses.
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

// reply.go schema:
// Forward-compatible: unknown strings don't break decoding.

enum ReplyStage: Decodable, Equatable, CustomStringConvertible {
    case msg, inject, approve, arm, disarm
    case unknown(String)

    var description: String {
        switch self {
        case .msg: return "msg"
        case .inject: return "inject"
        case .approve: return "approve"
        case .arm: return "arm"
        case .disarm: return "disarm"
        case .unknown(let s): return "unknown(\(s))"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        switch raw {
        case "msg": self = .msg
        case "inject": self = .inject
        case "approve": self = .approve
        case "arm": self = .arm
        case "disarm": self = .disarm
        default: self = .unknown(raw)
        }
    }
}

enum ReplyReason: Decodable, Equatable, CustomStringConvertible {
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
    case unknown(String)

    var description: String {
        switch self {
        case .ok: return "ok"
        case .clipboard_fallback: return "clipboard_fallback"
        case .inject_unavailable_wayland: return "inject_unavailable_wayland"
        case .not_armed: return "not_armed"
        case .needs_approve: return "needs_approve"
        case .not_paired: return "not_paired"
        case .bad_request: return "bad_request"
        case .bad_timestamp: return "bad_timestamp"
        case .replay: return "replay"
        case .rate_limit: return "rate_limit"
        case .crypto_fail: return "crypto_fail"
        case .internal_error: return "internal_error"
        case .unknown(let s): return "unknown(\(s))"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        switch raw {
        case "ok": self = .ok
        case "clipboard_fallback": self = .clipboard_fallback
        case "inject_unavailable_wayland": self = .inject_unavailable_wayland
        case "not_armed": self = .not_armed
        case "needs_approve": self = .needs_approve
        case "not_paired": self = .not_paired
        case "bad_request": self = .bad_request
        case "bad_timestamp": self = .bad_timestamp
        case "replay": self = .replay
        case "rate_limit": self = .rate_limit
        case "crypto_fail": self = .crypto_fail
        case "internal_error": self = .internal_error
        default: self = .unknown(raw)
        }
    }
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
        let nonce = try await readExact(conn, count: 24)
        let ct = try await receive(conn, min: 1, max: min(4096, maxBytes - 24))
        if ct.isEmpty {
            throw NovaKeyPairError.protocolError("empty ack ciphertext")
        }

        var ack = Data()
        ack.reserveCapacity(nonce.count + ct.count)
        ack.append(nonce)
        ack.append(ct)

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

private struct DaemonReply: Decodable {
    let v: Int
    let status: UInt8
    let stage: ReplyStage
    let reason: ReplyReason
    let msg: String
    let ts_unix: Int64
    let req_id: UInt64

    enum CodingKeys: String, CodingKey {
        case v, status, stage, reason, msg, ts_unix, req_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Version: default to 1 if absent
        self.v = (try c.decodeIfPresent(Int.self, forKey: .v)) ?? 1

        // status may arrive as Int in some encoders/bridges; tolerate both.
        if let u8 = try c.decodeIfPresent(UInt8.self, forKey: .status) {
            self.status = u8
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .status) {
            self.status = UInt8(clamping: i)
        } else {
            self.status = 0x7F // internal error fallback
        }

        // stage/reason: tolerant Decodable impls; tolerate missing/null.
        if let st = try c.decodeIfPresent(ReplyStage.self, forKey: .stage) {
            self.stage = st
        } else {
            self.stage = .unknown("missing")
        }

        if let rsn = try c.decodeIfPresent(ReplyReason.self, forKey: .reason) {
            self.reason = rsn
        } else {
            self.reason = .unknown("missing")
        }

        // msg can be missing or null
        self.msg = (try c.decodeIfPresent(String.self, forKey: .msg)) ?? ""

        // timestamps/req id can be missing
        self.ts_unix = (try c.decodeIfPresent(Int64.self, forKey: .ts_unix)) ?? 0
        self.req_id = (try c.decodeIfPresent(UInt64.self, forKey: .req_id)) ?? 0
    }
}

// Alternate schema for policy/deny/fallback responses (forward compatible).
private struct AltReply: Decodable {
    let ok: Bool?
    let status: String?
    let stage: String?
    let reason: String?
    let error: String?
    let message: String?
    let msg: String?
    let clipboard_fallback: Bool?
    let ts_unix: Int64?
    let req_id: UInt64?

    enum CodingKeys: String, CodingKey {
        case ok, status, stage, reason, error, message, msg
        case clipboard_fallback
        case ts_unix
        case req_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        ok = try? c.decodeIfPresent(Bool.self, forKey: .ok)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        stage = try? c.decodeIfPresent(String.self, forKey: .stage)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        msg = try? c.decodeIfPresent(String.self, forKey: .msg)
        clipboard_fallback = try? c.decodeIfPresent(Bool.self, forKey: .clipboard_fallback)
        ts_unix = try? c.decodeIfPresent(Int64.self, forKey: .ts_unix)

        if let u = try? c.decodeIfPresent(UInt64.self, forKey: .req_id) {
            req_id = u
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .req_id), let u = UInt64(s) {
            req_id = u
        } else {
            req_id = nil
        }
    }

    var bestMessage: String {
        let t = (message ?? msg ?? error ?? reason ?? status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t
    }
}

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

        var description: String {
            switch self {
            case .ok: return "ok"
            case .notArmed: return "notArmed"
            case .needsApprove: return "needsApprove"
            case .notPaired: return "notPaired"
            case .badRequest: return "badRequest"
            case .badTimestamp: return "badTimestamp"
            case .replay: return "replay"
            case .rateLimit: return "rateLimit"
            case .cryptoFail: return "cryptoFail"
            case .okClipboard: return "okClipboard"
            case .internalError: return "internalError"
            case .unknown: return "unknown"
            }
        }
    }

    struct ServerResponse {
        let status: NovaKeyClient.Status
        let message: String
        let stage: ReplyStage
        let reason: ReplyReason
        let reqID: UInt64
        let replyVersion: Int
        let tsUnix: Int64

        // Clipboard UX normalization
        var isClipboardFallback: Bool {
            status == .okClipboard ||
            reason == .clipboard_fallback ||
            reason == .inject_unavailable_wayland
        }

        var userFacingMessage: String {
            if isClipboardFallback {
                return "Copied to clipboard. Paste into the focused field."
            }
            let t = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "No message from server." : t
        }
    }

    enum ClientError: Error, LocalizedError {
        case invalidHost
        case connectFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .invalidHost: return "Invalid host"
            case .connectFailed(let e): return "Connect failed: \(e?.localizedDescription ?? "unknown")"
            }
        }
    }

    // MARK: Public API

    func sendApprove(pairing: PairingRecord) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildApproveFrame(pairing: pairing)
        let data = try await sendRaw(frame: frame, host: pairing.serverHost, port: pairing.serverPort)
        return parseServerResponse(data)
    }

    func sendInject(secret: String, pairing: PairingRecord) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildInjectFrame(pairing: pairing, secret: secret)
        let data = try await sendRaw(frame: frame, host: pairing.serverHost, port: pairing.serverPort)
        return parseServerResponse(data)
    }

    func sendArm(pairing: PairingRecord, durationMs: Int? = nil) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildArmFrame(pairing: pairing, durationMs: durationMs)
        let data = try await sendRaw(frame: frame, host: pairing.serverHost, port: pairing.serverPort)
        return parseServerResponse(data)
    }

    func sendDisarm(pairing: PairingRecord) async throws -> ServerResponse {
        let frame = try NovaKeyProtocolV3.buildDisarmFrame(pairing: pairing)
        let data = try await sendRaw(frame: frame, host: pairing.serverHost, port: pairing.serverPort)
        return parseServerResponse(data)
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
                    conn.stateUpdateHandler = nil
                    waiter.cont?.resume(returning: ())
                    waiter.cont = nil

                case .failed(let e):
                    waiter.finished = true
                    conn.stateUpdateHandler = nil
                    waiter.cont?.resume(throwing: ClientError.connectFailed(e))
                    waiter.cont = nil

                case .cancelled:
                    waiter.finished = true
                    conn.stateUpdateHandler = nil
                    waiter.cont?.resume(throwing: ClientError.connectFailed(nil))
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
            conn.receive(minimumIncompleteLength: min, maximumLength: max) { data, _, isComplete, err in
                if let err {
                    cont.resume(throwing: err)
                    return
                }
                if isComplete {
                    cont.resume(returning: data ?? Data())
                    return
                }
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

    // MARK: Reply parsing (non-crashing, schema-flexible)

    private func parseServerResponse(_ data: Data) -> ServerResponse {
        let trimmedAll = data.trimmingTrailingNewlines()

        // Decode only the first JSON line if multiple are present.
        let firstLine: Data = {
            if let nl = trimmedAll.firstIndex(of: 0x0A) { // \n
                return trimmedAll.prefix(upTo: nl)
            }
            return trimmedAll
        }()

        guard !firstLine.isEmpty else {
            return ServerResponse(
                status: .internalError,
                message: "Empty response from server.",
                stage: .unknown("missing"),
                reason: .unknown("empty_response"),
                reqID: 0,
                replyVersion: 0,
                tsUnix: 0
            )
        }

        // 1) Primary schema
        if let d = try? JSONDecoder().decode(DaemonReply.self, from: firstLine) {
            return ServerResponse(
                status: Status.from(raw: d.status),
                message: d.msg,
                stage: d.stage,
                reason: d.reason,
                reqID: d.req_id,
                replyVersion: d.v,
                tsUnix: d.ts_unix
            )
        }

        // 2) Alternate schema (policy/deny/fallback)
        if let a = try? JSONDecoder().decode(AltReply.self, from: firstLine) {
            let msg = a.bestMessage.isEmpty ? "Server replied." : a.bestMessage

            let mappedReason: ReplyReason = {
                let r = (a.reason ?? a.error ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if r.contains("clipboard") { return .clipboard_fallback }
                if r.contains("inject_unavailable_wayland") { return .inject_unavailable_wayland }
                if r.contains("needs_approve") || r.contains("needs-approve") { return .needs_approve }
                if r.contains("not_armed") { return .not_armed }
                if r.contains("not_paired") { return .not_paired }
                if r.contains("rate") { return .rate_limit }
                if r.contains("bad_timestamp") { return .bad_timestamp }
                if r.contains("replay") { return .replay }
                if r.contains("crypto") { return .crypto_fail }
                if r.contains("internal") { return .internal_error }
                if r.contains("bad") { return .bad_request }
                return r.isEmpty ? .unknown("alt_missing_reason") : .unknown(r)
            }()

            let mappedStage: ReplyStage = {
                let s = (a.stage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !s.isEmpty else { return .unknown("alt_missing_stage") }
                switch s {
                case "msg": return .msg
                case "inject": return .inject
                case "approve": return .approve
                case "arm": return .arm
                case "disarm": return .disarm
                default: return .unknown(s)
                }
            }()

            let mappedStatus: Status = {
                if a.clipboard_fallback == true { return .okClipboard }
                if a.ok == true { return .ok }
                // policy denies / target blocked should be non-success but NOT internal error
                return .badRequest
            }()

            return ServerResponse(
                status: mappedStatus,
                message: msg,
                stage: mappedStage,
                reason: mappedReason,
                reqID: a.req_id ?? 0,
                replyVersion: 0,
                tsUnix: a.ts_unix ?? 0
            )
        }

        // 3) Raw fallback (never throw, never crash)
        let raw = String(decoding: firstLine, as: UTF8.self)
        return ServerResponse(
            status: .internalError,
            message: "Unexpected server reply: \(raw)",
            stage: .unknown("decode_failed"),
            reason: .unknown("decode_failed"),
            reqID: 0,
            replyVersion: 0,
            tsUnix: 0
        )
    }
}

private extension Data {
    func trimmingTrailingNewlines() -> Data {
        var d = self
        while let last = d.last, last == 0x0A || last == 0x0D { d.removeLast() }
        return d
    }
}
