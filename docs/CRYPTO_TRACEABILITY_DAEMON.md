# Cryptographic Traceability – Daemon Alignment
**NovaKey Desktop Daemon (cmd/novakey)**

_Last updated: 2025-12-26_

This document maps NovaKey’s cryptographic/security claims to concrete daemon
implementation locations (Go), using exact file:line anchors from:

`~/GitRepos/NovaKey-Daemon/cmd/novakey/*`

It complements:
- iOS: `docs/CRYPTO_TRACEABILITY.md`
- System design: `docs/CRYPTO_APPENDIX.md`

---

## 1. Crypto Responsibilities in the Daemon

The daemon is responsible for:

- **Post-quantum key establishment (ML-KEM-768 / Kyber768)** server-side (decapsulation)
- **Deriving a session AEAD key** via **HKDF-SHA256**
- **Decrypting & authenticating frames** using **XChaCha20-Poly1305**
- **Replay detection** via a nonce cache (deviceID → nonceHex)
- Passing verified plaintext to policy gates and injection logic

---

## 2. Primary Crypto Anchors (Exact Locations)

### 2.1 Post-Quantum KEM (ML-KEM-768 / Kyber768)

**KEM library import:**
- `cmd/novakey/pairing_proto.go:19` imports `filippo.io/mlkem768`

**Pairing blob includes Kyber pubkey field:**
- `cmd/novakey/pairing_proto.go:34` `KyberPubB64 string \`json:"kyber_pub_b64"\``

**Ciphertext size check + decapsulation:**
- `cmd/novakey/pairing_proto.go:141` checks ciphertext size
- `cmd/novakey/pairing_proto.go:145` `sharedKem, err := mlkem768.Decapsulate(serverDecapKey, ct)`

**Claim supported:** daemon performs **ML-KEM-768 decapsulation** and produces `sharedKem` (the KEM shared secret).

---

### 2.2 HKDF-SHA256 Session Key Derivation

**HKDF import:**
- `cmd/novakey/crypto.go:18` imports `golang.org/x/crypto/hkdf`

**Derive AEAD key using HKDF-SHA256:**
- `cmd/novakey/crypto.go:153` `h := hkdf.New(sha256.New, sharedKem, deviceKey, []byte("NovaKey v3 AEAD key"))`
- `cmd/novakey/crypto.go:154` allocates output key sized to `chacha20poly1305.KeySize`
- `cmd/novakey/crypto.go:156` reads derived key from HKDF reader

**Claim supported:** `sharedKem` is **not used directly** as an AEAD key; it is fed through **HKDF-SHA256** to derive an AEAD key, with context string `"NovaKey v3 AEAD key"`.

---

### 2.3 AEAD: XChaCha20-Poly1305 (via chacha20poly1305.NewX)

**AEAD library import:**
- `cmd/novakey/crypto.go:17` imports `golang.org/x/crypto/chacha20poly1305`

**AEAD key size enforcement:**
- `cmd/novakey/crypto.go:143–145` checks derived key length equals `chacha20poly1305.KeySize`

**Construct XChaCha20-Poly1305 instance:**
- `cmd/novakey/crypto.go:254` `aead, err := chacha20poly1305.NewX(aeadKey)`

**Nonce size determined from AEAD:**
- `cmd/novakey/crypto.go:260` `nonceLen := aead.NonceSize()`

**Nonce + ciphertext parsing:**
- `cmd/novakey/crypto.go:261–266` validates frame length and splits `rest` into `nonce` and `ciphertext`

**Authenticated decryption:**
- `cmd/novakey/crypto.go:268` `plaintext, err := aead.Open(nil, nonce, ciphertext, header)`

**Claim supported:** daemon uses **XChaCha20-Poly1305** (NewX) and enforces authenticated decryption with AAD (`header`).

---

### 2.4 Replay Detection (Nonce Cache)

**Replay cache structure:**
- `cmd/novakey/crypto.go:56` `replayCache = make(map[string]map[string]int64) // deviceID -> nonceHex -> seenAtUnix`

**Freshness + rate gating is checked before allowing message:**
- `cmd/novakey/crypto.go:171` `validateFreshnessAndRate(devID, nonce, ts)`

**Nonce tracked per device, replay rejected:**
- `cmd/novakey/crypto.go:286` `nonceHex := hex.EncodeToString(nonce)`
- `cmd/novakey/crypto.go:323–324` rejects if nonce already seen (“replay detected…”)
- `cmd/novakey/crypto.go:328` stores nonce as seen

**Claim supported:** replay attempts using the same nonce for a deviceID are detected and rejected.

---

## 3. Where Decrypted Data Goes (Policy Gates + Injection)

After cryptographic verification, the daemon applies policy and operational gates
(e.g., two-man approval, target policy checks, armed gate) before injection.

Two-man approval gate behavior is visible in:
- `cmd/novakey/msg_handler.go:69–76` approve messages handled and windowed
- `cmd/novakey/msg_handler.go:138–154` blocks injection if not approved / expired, returns “needs approve”
- `cmd/novakey/msg_handler.go:129–130` injection is serialized with a mutex

(These are not cryptographic primitives, but they are part of the end-to-end
security controls around decrypted plaintext.)

---

## 4. Claim-to-Code Traceability Table (Daemon)

| Claim | What must be true | Where proven | Verification |
|------|-------------------|-------------|--------------|
| ML-KEM-768 (Kyber768) used for pairing/session establishment | Daemon decapsulates ML-KEM ciphertext to produce `sharedKem` | `pairing_proto.go:19,34,141–145` | Integration pairing succeeds; sharedKem derived |
| Shared secret not used directly | `sharedKem` flows into HKDF | `crypto.go:153–156` | Unit test: derived key length equals `KeySize` |
| HKDF-SHA256 session key derivation | HKDF uses SHA256 and context string | `crypto.go:153–156` | Unit test: domain separation (if multiple infos used elsewhere) |
| XChaCha20-Poly1305 AEAD | NewX used; Open called with AAD | `crypto.go:254,268` | Roundtrip + tamper tests |
| Fresh nonce per frame; nonce parsed correctly | nonceLen from AEAD, nonce extracted | `crypto.go:260–266` | Unit test: decode frame layout and assert nonceLen match |
| Replay resistance | Nonce cache rejects reuse per device | `crypto.go:56,171,286,323–328` | Integration replay test: resend same frame => rejected |
| Verified plaintext gated before injection | Gates block unsafe actions even after decrypt | `msg_handler.go:92–200` | Integration tests for two-man + policy gates |

---

## 5. Notes / Audit-Honesty

- The daemon’s AEAD implementation is **explicit** and directly auditable in Go.
- The iOS app’s AEAD implementation may live in a native module; however, the daemon
  side is unambiguous: **XChaCha20-Poly1305 via `chacha20poly1305.NewX`**.
- Replay detection is implemented as a **nonce cache per deviceID**.

---
