# 🧠 NovaKey Cryptography Appendix

This document describes NovaKey’s cryptographic design decisions and limitations.

---

## Design Principles

- Use standardized, reviewed primitives
- Avoid protocol invention
- Fail closed
- Bind cryptography to device identity

---

## Pairing Protocol

Each pairing establishes:
- Unique device ID
- 32-byte symmetric device key
- Server ML-KEM-768 public key

Pairing is authenticated via:
- QR bootstrap token
- Host & port binding
- Time-limited validity

---

## Message Encryption

All messages use:

- ML-KEM-768 for key encapsulation
- HKDF-SHA-256 for key derivation
- XChaCha20-Poly1305 for AEAD

Properties:
- Confidentiality
- Integrity
- Authenticity
- Replay protection

---

## Replay Protection

Messages include:
- Timestamps
- Nonces
- Per-device tracking

Replays are rejected automatically.

---

## Clipboard Fallback

Clipboard fallback:
- Is explicitly enabled
- Is visible to the user
- Is time-limited
- Is local-only (no Universal Clipboard)

Clipboard is treated as **lower trust** than injection.

---

## Explicit Non-Goals

NovaKey does not attempt to:
- Protect against compromised OS
- Obscure traffic patterns
- Provide deniability

These constraints are intentional.

