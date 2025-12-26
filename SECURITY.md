# 🔐 NovaKey iOS App — Security Overview

NovaKey is designed to transmit high-value secrets from an iOS device to a trusted local listener **without exposing those secrets to keyboards, logs, analytics, or cloud services**.

This document defines NovaKey’s threat model, cryptographic design, test-backed guarantees, and privacy posture.

---

## 1. Threat Model (STRIDE)

NovaKey uses the STRIDE framework to systematically identify and mitigate threats.

### STRIDE Table

| Threat | Description | Mitigation | Residual Risk |
|------|------------|-----------|---------------|
| Spoofing | Fake listener impersonation | Pairing QR + host:port binding | User pairs malicious host |
| Tampering | Message modification | AEAD (XChaCha20-Poly1305) | Compromised OS |
| Repudiation | User denies sending | Explicit UI + biometrics | Social dispute |
| Info Disclosure | Secret leakage | Keychain + redacted logs | OS compromise |
| DoS | Blocked sending | Timeouts + retries | Network failure |
| Privilege Escalation | Unauthorized send | Biometric + approval gates | Trusted daemon misbehavior |

---

## 2. Trust Boundaries

### Trusted
- iOS Secure Enclave & Keychain
- Explicit user actions
- Paired listener after verification

### Untrusted
- Network
- Clipboard after timeout
- Remote endpoints
- Background processes

NovaKey **fails closed** across all trust boundaries.

---

## 3. Cryptography Summary

| Purpose | Primitive |
|------|---------|
| Key exchange | ML-KEM-768 |
| Encryption | XChaCha20-Poly1305 |
| Authentication | Per-device symmetric keys |
| Replay protection | Nonces + timestamps |

> NovaKey does **not** invent cryptography.

---

## 4. Storage Guarantees

- Secrets are **never stored in plaintext**
- All secrets reside in **iOS Keychain**
- Secrets are never logged or uploaded
- Clipboard use is **explicit, local-only, and time-limited**

---

## 5. Test-Backed Security Claims

Every security property is enforced by automated tests.

| Claim | Tests |
|-----|------|
| Secrets require biometrics | `VaultAuthTests` |
| Pairing mismatch rejected | `PairingManagerTests` |
| Replay rejected | `ProtocolReplayTests` |
| Clipboard auto-clear | `ClipboardManagerTests` |
| `.okClipboard` treated as success | `ClientStatusTests` |

---

## 6. Privacy & App Store Alignment

NovaKey:
- ❌ Collects no personal data
- ❌ Uses no analytics
- ❌ Performs no tracking
- ❌ Uploads no secrets

All data is stored **locally on the device**.

---

## 7. Responsible Disclosure

📧 [security@novakey.app](mailto:security@novakey.app)  
🔑 **My PGP Key** https://downloads.osbornepro.com/publickey.asc  
🔐 Encrypted reports welcome  
🚫 Do not disclose vulnerabilities publicly

---

## 8. What NovaKey Does NOT Claim

- Protection from compromised OS
- Protection from malicious paired listener
- Anonymity
- Forward secrecy beyond protocol design

Security is **explicit, intentional, and user-controlled**.
