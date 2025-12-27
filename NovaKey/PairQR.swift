//
//  PairQR.swift
//  NovaKey
//
//  QR contents (bootstrap link schema; NOT crypto protocol version):
//    novakey://pair?v=3|4&host=...&port=...&token=...&fp=...&exp=...
//    novakey://pair?v=3|4&addr=host:port&token=...
//
//  NOTE: Allowing v=4 here does NOT mean “crypto v4”.
//  It only means the QR/URL format version. Crypto remains NovaKey v3.
//

import Foundation
// v optional; NovaKey uses v3 on iOS; ignore any other value (daemon may emit v=4)
let v: Int = 3

enum PairQRDecodeError: Error, LocalizedError, Equatable {
    case notNovaKeyPair
    case missingParam(String)
    case badPort
    case expired
    case badResponse
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .notNovaKeyPair: return "Not a NovaKey pairing QR code."
        case .missingParam(let p): return "Missing QR parameter: \(p)"
        case .badPort: return "Invalid port in QR code."
        case .expired: return "This QR code has expired. Generate a new one on the daemon."
        case .badResponse: return "Unexpected QR code format."
        case .unsupportedVersion(let v): return "Unsupported pairing QR version: v=\(v)"
        }
    }
}

struct PairBootstrapLink: Equatable {
    /// QR schema version (3 or 4). Not the crypto protocol version.
    let v: Int
    let host: String
    let port: Int
    let token: String
    let fp16Hex: String?
    let expUnix: Int64?
}

func decodeNovaKeyPairQRLink(_ payload: String) throws -> PairBootstrapLink {
    guard let url = URL(string: payload) else {
        throw PairQRDecodeError.notNovaKeyPair
    }
    guard (url.scheme ?? "").lowercased() == "novakey" else {
        throw PairQRDecodeError.notNovaKeyPair
    }

    // Handle multiple possible shapes:
    //  1) novakey://pair?...        => host="", path="/pair"
    //  2) novakey://pairing?...     => host="", path="/pairing"
    //  3) novakey://x/pair?...      => host="x", path="/pair"
    //  4) novakey://pair?... if encoded as novakey://pair (no slash) could put "pair" in host
    let hostLower = (url.host ?? "").lowercased()
    let pathLower = url.path.lowercased()

    let looksLikePair: Bool = {
        if hostLower == "pair" || hostLower == "pairing" { return true }
        if pathLower == "/pair" || pathLower == "/pairing" { return true }
        if pathLower.hasPrefix("/pair/") || pathLower.hasPrefix("/pairing/") { return true }
        if pathLower.contains("/pair") { return true } // last resort
        return false
    }()

    guard looksLikePair else {
        throw PairQRDecodeError.notNovaKeyPair
    }

    guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw PairQRDecodeError.notNovaKeyPair
    }

    let items = comps.queryItems ?? []

    // v is QR schema version. Default to 3 if absent.
    let v: Int = {
        if let vStr = items.first(where: { $0.name == "v" })?.value,
           let parsed = Int(vStr) {
            return parsed
        }
        return 3
    }()

    // Allow v=3 or v=4 (QR schema), reject anything else.
    guard v == 3 || v == 4 else {
        throw PairQRDecodeError.unsupportedVersion(v)
    }

    guard let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty else {
        throw PairQRDecodeError.missingParam("token")
    }

    // Optional exp
    let expUnix: Int64? = {
        guard let s = items.first(where: { $0.name == "exp" })?.value,
              let n = Int64(s) else { return nil }
        return n
    }()

    if let expUnix, expUnix < Int64(Date().timeIntervalSince1970) {
        throw PairQRDecodeError.expired
    }

    // Optional fp
    let fp16Hex: String? = {
        let s = items.first(where: { $0.name == "fp" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }()

    // Either addr=host:port OR host/port
    if let addr = items.first(where: { $0.name == "addr" || $0.name == "server" || $0.name == "server_addr" })?.value,
       !addr.isEmpty {
        let (h, p) = try parseHostPort(addr)
        return PairBootstrapLink(v: v, host: h, port: p, token: token, fp16Hex: fp16Hex, expUnix: expUnix)
    }

    guard let host = items.first(where: { $0.name == "host" })?.value, !host.isEmpty else {
        throw PairQRDecodeError.missingParam("host")
    }

    guard let portStr = items.first(where: { $0.name == "port" })?.value,
          let port = Int(portStr),
          port > 0 else {
        throw PairQRDecodeError.badPort
    }

    return PairBootstrapLink(v: v, host: host, port: port, token: token, fp16Hex: fp16Hex, expUnix: expUnix)
}

private func parseHostPort(_ s: String) throws -> (String, Int) {
    let parts = s.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2,
          let port = Int(parts[1]),
          port > 0 else {
        throw PairQRDecodeError.badPort
    }
    let host = String(parts[0])
    guard !host.isEmpty else { throw PairQRDecodeError.badResponse }
    return (host, port)
}
