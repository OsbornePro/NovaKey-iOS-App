//
//  NovaKeyWire.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import Foundation

enum NovaKeyWire {
    // Common patterns:
    // - length-prefixed frames (u32 big endian) OR
    // - newline-delimited JSON
    // We'll support BOTH with a switch until we confirm your protocol.

    enum Framing {
        case lengthPrefixedU32BE
        case newlineDelimited
    }

    struct ServerReply: Decodable {
        let ok: Bool
        let error: String?
    }

    // You will replace / extend these once we read PROTOCOL.md
    struct PlainSend: Codable {
        let secretName: String
        let secretValue: String
        let timestamp: Int64
    }

    // Protocol usually has an envelope for encryption/auth
    struct Envelope: Codable {
        let version: Int
        let type: String
        let deviceId: String?
        let timestamp: Int64
        let nonce: String?
        let payload: String // base64, or JSON string, etc.
        let mac: String?
    }

    static func encodeFrame(_ data: Data, framing: Framing) -> Data {
        switch framing {
        case .lengthPrefixedU32BE:
            var len = UInt32(data.count).bigEndian
            var out = Data(bytes: &len, count: 4)
            out.append(data)
            return out
        case .newlineDelimited:
            var out = data
            out.append(0x0A) // '\n'
            return out
        }
    }

    static func decodeLengthPrefixedFrames(from buffer: inout Data) -> [Data] {
        var frames: [Data] = []
        while buffer.count >= 4 {
            let lenBE = buffer.prefix(4)
            let len = lenBE.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard buffer.count >= 4 + Int(len) else { break }
            let frame = buffer.subdata(in: 4..<(4 + Int(len)))
            frames.append(frame)
            buffer.removeSubrange(0..<(4 + Int(len)))
        }
        return frames
    }

    static func nowUnixSeconds() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
