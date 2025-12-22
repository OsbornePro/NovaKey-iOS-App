//
//  PairQR.swift
//  NovaKey
//
//  Supports BOTH:
//   - v=2 “small QR” bootstrap flow (recommended):
//       QR:  novakey://pair?v=2&host=...&port=...&token=...
//       GET  http://host:port/pair/bootstrap?token=...
//       POST http://host:port/pair/complete?token=...
//
//   - Legacy “big QR” flow (optional):
//       QR:  novakey://pair?data=...  (base64url(zlib(JSON)))
//

import Foundation
import Compression

enum PairQRDecodeError: Error, LocalizedError {
    case notNovaKeyPair
    case missingParam(String)
    case badPort
    case badBase64
    case decompressFailed
    case badJSON
    case expired
    case network(String)
    case httpStatus(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notNovaKeyPair: return "Not a NovaKey pairing QR code."
        case .missingParam(let p): return "Missing QR parameter: \(p)"
        case .badPort: return "Invalid port in QR code."
        case .badBase64: return "Invalid QR payload encoding."
        case .decompressFailed: return "Could not decode QR payload."
        case .badJSON: return "Invalid QR payload data."
        case .expired: return "This QR code has expired. Generate a new one on the daemon."
        case .network(let s): return "Network error: \(s)"
        case .httpStatus(let c): return "Daemon returned HTTP \(c)"
        case .badResponse: return "Unexpected daemon response."
        }
    }
}

/// The small QR content (what the phone scans)
struct PairBootstrapLink: Equatable {
    let v: Int
    let host: String
    let port: Int      // pairing API port (listenPort + 2 in your daemon)
    let token: String
}

/// The big blob returned by GET /pair/bootstrap
struct PairBootstrapResponse: Decodable {
    let v: Int
    let device_id: String
    let device_key_hex: String
    let server_addr: String
    let server_kyber768_pub: String
    let expires_at_unix: Int64
}

/// Legacy “big QR” payload (if you still ever generate data=... somewhere)
struct PairQR: Decodable {
    let pair_v: Int
    let device_id: String
    let device_key_hex: String
    let server_kyber_pub_b64: String
    let listen_port: Int
    let issued_at_unix: Int64
    let expires_at_unix: Int64
}

// MARK: - Decode QR

/// Decode either:
///  - New small QR: novakey://pair?v=2&host=...&port=...&token=...
///  - Legacy big QR: novakey://pair?data=... (zlib+base64url JSON)
func decodeNovaKeyPairQRLink(_ payload: String) throws -> PairBootstrapLink {
    guard let url = URL(string: payload),
          url.scheme == "novakey",
          url.host == "pair",
          let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { throw PairQRDecodeError.notNovaKeyPair }

    let items = comps.queryItems ?? []

    // New format?
    if let vStr = items.first(where: { $0.name == "v" })?.value,
       let v = Int(vStr),
       v == 2 {

        guard let host = items.first(where: { $0.name == "host" })?.value, !host.isEmpty else {
            throw PairQRDecodeError.missingParam("host")
        }
        guard let portStr = items.first(where: { $0.name == "port" })?.value, let port = Int(portStr), port > 0 else {
            throw PairQRDecodeError.badPort
        }
        guard let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty else {
            throw PairQRDecodeError.missingParam("token")
        }

        return PairBootstrapLink(v: v, host: host, port: port, token: token)
    }

    // Legacy big QR?
    if items.first(where: { $0.name == "data" })?.value != nil {
        // Call legacy decoder instead, if you want to support it.
        throw PairQRDecodeError.badResponse
    }

    throw PairQRDecodeError.notNovaKeyPair
}

/// Legacy decode (optional) — only used if you still generate big “data=” QRs.
/// Safe to keep for backward compat.
func decodeNovaKeyPairQR(_ payload: String) throws -> PairQR {
    guard let url = URL(string: payload),
          url.scheme == "novakey",
          url.host == "pair",
          let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let dataParam = comps.queryItems?.first(where: { $0.name == "data" })?.value
    else { throw PairQRDecodeError.notNovaKeyPair }

    guard let compressed = Data(base64URLEncoded: dataParam) else {
        throw PairQRDecodeError.badBase64
    }

    guard let jsonData = compressed.decompressedZlib() else {
        throw PairQRDecodeError.decompressFailed
    }

    let qr: PairQR
    do {
        qr = try JSONDecoder().decode(PairQR.self, from: jsonData)
    } catch {
        throw PairQRDecodeError.badJSON
    }

    let now = Int64(Date().timeIntervalSince1970)
    if qr.expires_at_unix < now {
        throw PairQRDecodeError.expired
    }

    return qr
}

// MARK: - Bootstrap Fetch + Complete

func fetchPairBootstrap(_ link: PairBootstrapLink) async throws -> PairBootstrapResponse {
    var comps = URLComponents()
    comps.scheme = "http"
    comps.host = link.host
    comps.port = link.port
    comps.path = "/pair/bootstrap"
    comps.queryItems = [URLQueryItem(name: "token", value: link.token)]

    guard let url = comps.url else { throw PairQRDecodeError.badResponse }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.timeoutInterval = 5

    do {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw PairQRDecodeError.badResponse }
        guard (200...299).contains(http.statusCode) else { throw PairQRDecodeError.httpStatus(http.statusCode) }

        let decoded = try JSONDecoder().decode(PairBootstrapResponse.self, from: data)

        let now = Int64(Date().timeIntervalSince1970)
        if decoded.expires_at_unix < now {
            throw PairQRDecodeError.expired
        }

        return decoded
    } catch let e as PairQRDecodeError {
        throw e
    } catch {
        throw PairQRDecodeError.network(error.localizedDescription)
    }
}

func postPairComplete(_ link: PairBootstrapLink) async throws {
    var comps = URLComponents()
    comps.scheme = "http"
    comps.host = link.host
    comps.port = link.port
    comps.path = "/pair/complete"
    comps.queryItems = [URLQueryItem(name: "token", value: link.token)]

    guard let url = comps.url else { throw PairQRDecodeError.badResponse }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 5

    do {
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw PairQRDecodeError.badResponse }
        guard (200...299).contains(http.statusCode) else { throw PairQRDecodeError.httpStatus(http.statusCode) }
    } catch let e as PairQRDecodeError {
        throw e
    } catch {
        throw PairQRDecodeError.network(error.localizedDescription)
    }
}

// MARK: - Convert bootstrap -> PairingBlob JSON your PairingManager expects

/// Your PairingManager.parsePairingJSON expects:
/// { v, device_id, device_key_hex, server_addr, server_kyber768_pub }
func makePairingJSON(from bootstrap: PairBootstrapResponse) throws -> String {
    struct PairingBlob: Codable {
        let v: Int
        let device_id: String
        let device_key_hex: String
        let server_addr: String
        let server_kyber768_pub: String
    }

    let blob = PairingBlob(
        v: bootstrap.v,
        device_id: bootstrap.device_id,
        device_key_hex: bootstrap.device_key_hex,
        server_addr: bootstrap.server_addr,
        server_kyber768_pub: bootstrap.server_kyber768_pub
    )

    let data = try JSONEncoder().encode(blob)
    return String(decoding: data, as: UTF8.self)
}

// MARK: - Helpers

extension Data {
    init?(base64URLEncoded s: String) {
        var base64 = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - (base64.count % 4)) % 4
        base64 += String(repeating: "=", count: pad)
        self.init(base64Encoded: base64)
    }

    func decompressedZlib() -> Data? {
        (try? decompress(algorithm: COMPRESSION_ZLIB)) ?? nil
    }

    private func decompress(algorithm: compression_algorithm) throws -> Data {
        guard !isEmpty else { return Data() }

        return try withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) throws -> Data in
            guard let srcBase = srcPtr.baseAddress else { return Data() }

            let dstCapacity = Swift.max(count * 8, 64 * 1024)
            var dst = Data(count: dstCapacity)

            let decodedSize = dst.withUnsafeMutableBytes { dstPtr -> Int in
                guard let dstBase = dstPtr.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self),
                    dstCapacity,
                    srcBase.assumingMemoryBound(to: UInt8.self),
                    count,
                    nil,
                    algorithm
                )
            }

            guard decodedSize > 0 else { throw PairQRDecodeError.decompressFailed }
            dst.count = decodedSize
            return dst
        }
    }
}
