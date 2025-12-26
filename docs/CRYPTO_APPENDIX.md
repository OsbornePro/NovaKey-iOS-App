# Cryptographic Appendix
This appendix is part of the full cryptographic audit set.

➡️ **For complete iOS + daemon coverage, see:**  
[Crypto Audit Appendix (Combined, PDF)](NovaKey_Crypto_Audit_Appendix_Combined.pdf)

➡️ **For implementation mapping, see:**  
- [iOS Crypto Traceability](CRYPTO_TRACEABILITY.md)  
- [Daemon Crypto Traceability](CRYPTO_TRACEABILITY_DAEMON.md)


**NovaKey Secure Input System**

*Last updated: 2025-12-26*

> **Navigation**
>
> - 🔐 [Crypto Audit Appendix (Combined, PDF)](NovaKey_Crypto_Audit_Appendix_Combined.pdf)
> - 🧠 [Threat Model Diagram (PDF)](NovaKey_Threat_Model_Diagram.pdf)
> - 📋 [iOS Crypto Traceability](CRYPTO_TRACEABILITY.md)
> - 🖥️ [Daemon Crypto Traceability](CRYPTO_TRACEABILITY_DAEMON.md)
> - 🧪 [Security Test Plan](SECURITY_TEST_PLAN.md)

---

## 1. Goals & Threat Model Alignment

This appendix documents the cryptographic design of NovaKey to:

* Provide **confidentiality** and **integrity** for all transmitted user input
* Prevent **host spoofing**, **MITM**, and **replay attacks**
* Minimize long-term key exposure
* Avoid reliance on platform trust stores or cloud key escrow
* Remain compliant with **App Store privacy and encryption policies**

This appendix complements the STRIDE analysis in `SECURITY.md`.

---

## 2. Cryptographic Primitives

NovaKey uses **modern, conservative primitives** with well-understood security properties.

| Purpose                | Algorithm              | Notes                                |
| ---------------------- | ---------------------- | ------------------------------------ |
| Key exchange           | **Kyber768**           | NIST PQC finalist (ML-KEM)           |
| Symmetric encryption   | **XChaCha20-Poly1305** | 256-bit key, 192-bit nonce           |
| Key derivation         | **HKDF-SHA256**        | Domain-separated contexts            |
| Message authentication | **Poly1305**           | AEAD-integrated                      |
| Randomness             | OS CSPRNG              | `SecRandomCopyBytes` / `getrandom()` |

No deprecated or weakened primitives are used.

---

## 3. Post-Quantum Key Exchange (Kyber768)

### 3.1 Rationale

NovaKey uses **Kyber768** to protect against:

* Classical MITM attacks
* Passive recording with future quantum decryption
* Host impersonation during pairing

Kyber768 offers a conservative security margin with acceptable performance for short-lived sessions.

### 3.2 Usage Model

* Kyber is used **only during pairing / session establishment**
* Resulting shared secret is **never reused directly**
* Output feeds into HKDF to derive symmetric keys

```text
Kyber768
   ↓
Shared Secret
   ↓ HKDF-SHA256
Session Encryption Key
```

---

## 4. Session Key Derivation

All session keys are derived using **HKDF-SHA256** with strict domain separation.

### 4.1 Inputs

* Input Key Material (IKM): Kyber shared secret
* Salt: Session-unique random value
* Info: Protocol-specific context string

Example info strings:

```
novakey/session/encryption
novakey/session/authentication
```

This prevents cross-protocol key reuse.

---

## 5. Authenticated Encryption (XChaCha20-Poly1305)

### 5.1 Encryption Properties

NovaKey uses **XChaCha20-Poly1305** for all encrypted payloads:

* Confidentiality (ChaCha20 stream cipher)
* Integrity & authenticity (Poly1305 MAC)
* Extended nonce space (192-bit) eliminates nonce reuse risk

### 5.2 Nonce Handling

* Nonces are **randomly generated per message**
* Never reused under the same key
* Nonces are transmitted alongside ciphertext

No counters or deterministic nonce schemes are used.

---

## 6. Message Structure

Each encrypted message has the following conceptual structure:

```
[ Version ]
[ Message Type ]
[ Nonce ]
[ Ciphertext ]
[ Authentication Tag ]
```

The **message type** (e.g., typed input vs clipboard) is authenticated but not confidentially relied upon for security decisions.

---

## 7. Pairing & Trust Establishment

### 7.1 Initial Pairing

Pairing requires **explicit user confirmation** on the mobile device.

* Host identity (IP / port / fingerprint) is displayed
* User must approve before keys are persisted
* No silent or background trust establishment

### 7.2 Device Identity

After pairing:

* Devices are identified via stored public-key fingerprints
* No device identifiers are uploaded to servers
* Trust is strictly **local and user-controlled**

---

## 8. Replay Protection

NovaKey resists replay attacks using:

* Session-scoped encryption keys
* Fresh nonces per message
* Session teardown on disconnect

Captured ciphertexts cannot be replayed in future sessions.

---

## 9. Forward Secrecy

Each session establishes **new ephemeral keys**:

* Compromise of a session key does **not** compromise past sessions
* Long-term device compromise does not reveal historical input

---

## 10. Clipboard vs Typed Input Handling

From a cryptographic perspective:

* Clipboard and typed input are encrypted identically
* Both use the same AEAD construction
* Differentiation is **UI-only**, not security-critical

This avoids accidental side-channel leakage.

---

## 11. Data at Rest

### 11.1 Mobile Device

* Long-term pairing keys stored using OS secure storage
* No plaintext keystrokes or clipboard contents are persisted
* Keys are inaccessible to other apps

### 11.2 Desktop Host

* Pairing information stored encrypted at rest
* Platform-specific secure storage (e.g., DPAPI / Keychain)
* No input content is logged or retained

---

## 12. Cryptographic Agility

NovaKey is designed to allow:

* Replacement of Kyber if standards evolve
* Migration to future AEAD constructions
* Version-tagged protocol negotiation

Backward compatibility is explicitly versioned.

---

## 13. Non-Goals & Explicit Exclusions

NovaKey **does not attempt** to:

* Protect against a fully compromised host OS
* Prevent malicious keyboard drivers
* Obfuscate timing or keystroke length side-channels
* Act as a general VPN or network anonymization tool

These are out of scope by design.

---

## 14. Compliance & Review Notes

* Uses **standard, peer-reviewed cryptography**
* No proprietary or “home-grown” algorithms
* No cloud-based key escrow
* No user data collection or analytics tied to cryptographic material

This design complies with **Apple App Store encryption disclosure requirements**.

---

## 15. Summary

NovaKey’s cryptographic design emphasizes:

* **Post-quantum safety**
* **Strong authenticated encryption**
* **Explicit user trust decisions**
* **Minimal attack surface**
* **No cloud dependencies**

The system favors conservative choices over novelty and avoids unnecessary complexity.

---

**Related Documents**
- [Threat Model Diagram](NovaKey_Threat_Model_Diagram.pdf)
- [QR Pairing Visual](NovaKey_QR_Pairing_Visual.pdf)

