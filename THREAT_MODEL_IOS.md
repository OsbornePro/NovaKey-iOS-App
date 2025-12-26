# Threat Model — NovaKey iOS App

## Overview

The NovaKey iOS app is a **trusted secret origin**. It stores high-value secrets locally and transmits them securely to a paired NovaKey-Daemon instance for controlled injection into the active desktop application.

The design goal is to **reduce keyboard exposure**, **prevent network compromise**, and **fail safely** under hostile conditions.

---

## Assets Protected

* User secrets (passwords, recovery keys, tokens)
* Pairing credentials (per-device PSK)
* User intent (explicit approval before secret release)
* Biometric authentication state

---

## Trust Boundaries

| Boundary      | Description                                   |
| ------------- | --------------------------------------------- |
| iOS device    | Trusted, user-controlled, biometric protected |
| Paired daemon | Semi-trusted, explicitly paired               |
| Local network | Untrusted                                     |
| Internet      | Untrusted                                     |
| Desktop OS    | Potentially hostile (keyloggers, malware)     |

---

## Threats Considered

### Network Attacks

* Passive sniffing
* Active tampering / replay
* Unauthorized clients

**Mitigations**

* ML-KEM-768 + XChaCha20-Poly1305
* Per-device PSKs
* Timestamp freshness + replay cache
* No broadcast or discovery

---

### Malicious QR Codes / Phishing

* Attacker places a QR code to trick pairing

**Mitigations**

* One-time pairing token
* Public key fingerprint verification
* Explicit user confirmation: *“Pair with host:port?”*
* Pairing only allowed when daemon is in pairing mode

---

### Unauthorized Secret Release

* Background send
* Silent retries
* Automatic approvals

**Mitigations**

* Explicit user action required
* Biometric gating
* Optional “fresh biometric required”
* Two-man approval (daemon-side)

---

### Compromised Desktop

* Keyloggers
* Window spoofing
* Wayland blocking injection

**Mitigations**

* Clipboard fallback is explicit and visible
* No background clipboard monitoring
* No persistent plaintext storage
* Target policy enforcement on daemon

---

## Out of Scope (Explicitly)

* Fully compromised iOS device
* Jailbroken OS
* Physical attacks
* Malicious user installing spyware
* Compromised build pipeline

---

## Security Posture Summary

NovaKey assumes:

> **The desktop may be hostile; the phone is the root of trust.**

The app is designed to **fail closed**, **require user intent**, and **surface degraded security paths clearly** (e.g., clipboard fallback).
