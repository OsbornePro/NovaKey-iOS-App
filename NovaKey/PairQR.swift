//
//  PairQR.swift
//  NovaKey
//
//  QR contents (bootstrap link schema; NOT crypto protocol version):
//    novakey://pair?v=3&host=...&port=...&token=...&fp=...&exp=...
//    novakey://pair?v=3&addr=host:port&token=...&fp=...&exp=...
//

import Foundation

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
    let version: Int
    let host: String
    let port: Int
    let token: String       // token ONLY
    let fp16Hex: String?
    let expUnix: Int64?
}

func decodeNovaKeyPairQRLink(_ raw: String) throws -> PairBootstrapLink {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let comps = URLComponents(string: s) else {
        throw PairQRDecodeError.badResponse
    }
    guard (comps.scheme ?? "").lowercased() == "novakey" else {
        throw PairQRDecodeError.notNovaKeyPair
    }

    // Expect: novakey://pair?... (host part is "pair", path usually empty)
    let hostPart = (comps.host ?? "").lowercased()
    let pathPart = comps.path.lowercased()
    if hostPart != "pair" && pathPart != "/pair" && pathPart != "pair" {
        throw PairQRDecodeError.notNovaKeyPair
    }

    let items = comps.queryItems ?? []
    func q(_ name: String) -> String? {
        items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    let version = Int(q("v") ?? "") ?? 0
    if version != 0 && version != 3 {
        throw PairQRDecodeError.unsupportedVersion(version)
    }

    guard let token = q("token"), !token.isEmpty else {
        throw PairQRDecodeError.missingParam("token")
    }

    // host/port can be provided either as host+port OR addr=host:port
    var host: String?
    var port: Int?

    if let h = q("host"), !h.isEmpty,
       let pStr = q("port"), let p = Int(pStr), p > 0 {
        host = h
        port = p
    } else if let addr = q("addr"), !addr.isEmpty {
        let hp = try parseHostPort(addr)
        host = hp.0
        port = hp.1
    }

    guard let finalHost = host, !finalHost.isEmpty else {
        throw PairQRDecodeError.missingParam("host/addr")
    }
    guard let finalPort = port, finalPort > 0 else {
        throw PairQRDecodeError.badPort
    }

    let fp = q("fp")
    let exp: Int64? = {
        guard let s = q("exp"), !s.isEmpty else { return nil }
        return Int64(s)
    }()

    if let exp, exp > 0 {
        let now = Int64(Date().timeIntervalSince1970)
        if exp < now {
            throw PairQRDecodeError.expired
        }
    }

    return PairBootstrapLink(
        version: version,
        host: finalHost,
        port: finalPort,
        token: token,
        fp16Hex: fp,
        expUnix: exp
    )
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
