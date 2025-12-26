# Cryptographic Traceability Matrix
This document maps cryptographic claims to concrete **iOS application** code paths.

➡️ For full system coverage, also see:
- [Daemon Crypto Traceability](CRYPTO_TRACEABILITY_DAEMON.md)
- [Crypto Audit Appendix (Combined, PDF)](NovaKey_Crypto_Audit_Appendix_Combined.pdf)


**NovaKey iOS Application**

_Last updated: 2025-12-26_

This document maps each cryptographic and security claim made by NovaKey to
concrete implementation locations in the iOS codebase and corresponding tests.
Its purpose is to support internal review, third-party audits, and App Store
review inquiries.

Where cryptographic primitives are implemented in native modules, this document
explicitly calls that out; Swift code is responsible for orchestration, framing,
and trust decisions.

> **Navigation**
>
> - 🔐 [Crypto Audit Appendix (Combined, PDF)](NovaKey_Crypto_Audit_Appendix_Combined.pdf)
> - 🧠 [Threat Model Diagram (PDF)](NovaKey_Threat_Model_Diagram.pdf)
> - 📋 [iOS Crypto Traceability](CRYPTO_TRACEABILITY.md)
> - 🖥️ [Daemon Crypto Traceability](CRYPTO_TRACEABILITY_DAEMON.md)
> - 🧪 [Security Test Plan](SECURITY_TEST_PLAN.md)

---

## 1. High-Level Architecture Note

NovaKey’s cryptography is split across two layers:

1. **Native crypto module(s)**  
   * Implements ML-KEM (*Kyber768*) and AEAD (*XChaCha20-Poly1305*)
   * Exposed to Swift via C/Swift interop functions
   * Not implemented directly in Swift source

2. **Swift application layer**  
   * Handles pairing UX and trust decisions
   * Passes cryptographic material to/from native functions
   * Frames, stores, and transmits encrypted payloads
   * Never implements cryptographic primitives itself

This separation is intentional and documented.

---

## 2. Cryptographic Traceability Table

| Security / Crypto Claim | What must be true | Where proven in code | How verified |
|-------------------------|------------------|----------------------|--------------|
| **Post-quantum key exchange uses Kyber768 (*ML-KEM-768*)** | Pairing/session establishment uses server Kyber768 public key and invokes ML-KEM handshake | **Swift:**<br>• `NovaKey/PairQR.swift` — `server_kyber768_pub` parsed from QR bootstrap<br>• `NovaKey/PairingRecord.swift` — persisted `server_kyber768_pub` (*with backward-compat parsing*)<br>• `NovaKey/NovaKeyProtocolV3.swift` — calls `NovakeykemBuildApproveFrame(...)` and `NovakeykemBuildInjectFrame(...)` | Unit tests parse v3 pairing blobs containing `server_kyber768_pub`; integration pairing completes successfully |
| **Kyber implementation is native, not Swift** | Swift code must not implement ML-KEM math directly | No Kyber / ML-KEM primitives present in Swift source; only calls to `Novakeykem*` functions | Code inspection (`rg Kyber|mlkem`) confirms absence of primitive implementation |
| **Session keys derived via HKDF-SHA256** | Shared secret is input to HKDF; output key used for crypto, not raw secret | **Swift:**<br>• `NovaKey/VaultTransfer.swift` — `HKDF<SHA256>.deriveKey(...)` with explicit comment “HKDF-SHA256: password → SymmetricKey” | Unit tests validate domain separation and derived key length |
| **Authenticated encryption uses XChaCha20-Poly1305** | All encrypted payloads use AEAD with integrity protection | **Design:** Implemented in native crypto module<br>**Swift:** handles sealed payloads, nonce fields, and framing only | AEAD round-trip and tamper-failure tests exist in daemon; Swift layer tested via integration |
| **Swift does not implement AEAD primitives** | No XChaCha/Poly1305 code in Swift | `rg XChaCha|Poly1305|AEAD` returns documentation/tests only | Manual inspection + CI grep |
| **Unique nonce per encrypted message** | Each encrypted message carries a fresh nonce | **Swift:**<br>• `NovaKey/VaultTransfer.swift` — `nonceB64` field (*“nonce for cipher (base64). nil if included in combined*”)<br>• `NovaKey/NovaKeyWire.swift` — optional `nonce` field | Unit tests ensure nonce uniqueness across encryptions (*probabilistic*) |
| **Nonce may be embedded or explicit** | Wire format supports either explicit nonce field or combined sealed blob | **Swift:** comments at `VaultTransfer.swift` lines ~159, ~172 (*“included in combined”*) | Documented format; tests assert nonce extractability |
| **Replay resistance** | Captured ciphertext cannot be reused successfully | Session-scoped keys + per-message nonce; enforced by AEAD | Integration tests replay sealed payload → rejected or no-op |
| **Forward secrecy** | New session establishes new cryptographic keys | Pairing/session establishment always re-invokes ML-KEM handshake | Integration tests compare session keys across reconnects |
| **Clipboard vs typed input cryptographically identical** | Both input types encrypted identically; distinction is UI-only | **Swift:** same framing/encryption path; type is metadata only | Tests assert identical crypto behavior |
| **No plaintext keystrokes stored** | Input contents never persisted or logged | No disk writes in input pipeline; no logging of payloads | Static inspection + log-redaction tests |
| **Local trust establishment** | Pairing requires explicit user confirmation | Pairing UI + persisted pairing records | UI tests |

---

## 3. Native Crypto Boundary

The following native symbols are invoked from Swift and form the cryptographic
boundary:

```text
NovakeykemBuildApproveFrame(...)
NovakeykemBuildInjectFrame(...)
````

These functions:

* Consume pairing JSON and cryptographic material
* Perform ML-KEM (Kyber768) operations internally
* Produce sealed handshake frames consumed by Swift

Swift code treats these functions as opaque, trusted cryptographic providers.

---

## 4. Explicit Non-Claims

NovaKey **does not claim**:

* That cryptographic primitives are implemented in Swift
* That Swift code performs ML-KEM, XChaCha20, or Poly1305 operations
* Protection against a fully compromised host OS

These exclusions are intentional and documented.

---

## 5. Test Coverage Summary

| Area                                | Coverage              |
| ----------------------------------- | --------------------- |
| Pairing blob parsing (*Kyber pubkey*) | Unit tests            |
| HKDF derivation & domain separation | Unit tests            |
| AEAD correctness & tamper detection | Native + daemon tests |
| Nonce uniqueness                    | Unit tests            |
| Replay resistance                   | Integration tests     |
| Session freshness                   | Integration tests     |

---

## 6. Reviewer Notes (*App Store / Audit*)

* NovaKey uses standard, peer-reviewed cryptography
* Cryptographic primitives are isolated in native modules
* Swift code handles orchestration, not crypto math
* No cloud key escrow or analytics
* No user input contents stored or transmitted to servers

---

**Audit Context**
- [Threat Model Diagram](NovaKey_Threat_Model_Diagram.pdf)
- [Security Test Plan](SECURITY_TEST_PLAN.md)

