# 🔐 NovaKey iOS App – Security Overview

NovaKey is a companion iOS application designed to **securely store secrets locally** and **transmit them to a paired NovaKey listener** using strong cryptography and explicit user intent.

This document describes the **security model, guarantees, limitations, and threat assumptions** for the NovaKey iOS app.

---

## 📱 Scope

This document applies **only** to the **NovaKey iOS application**.

The NovaKey desktop daemon (*listener*) has its **own security model and configuration controls**, documented separately.

---

## 🧠 Threat Model

### Assets Protected

* Secrets stored in the iOS app (*passwords, tokens, sensitive text*)
* Pairing credentials used to authenticate a specific listener
* User intent (*preventing silent or background transmission*)

### Adversaries Considered

* Network attackers (*MITM, replay, injection*)
* Malicious or compromised remote servers
* Accidental misuse (*wrong host, wrong device*)
* Stolen iOS device without biometric access

### Adversaries *Not* Fully Defended Against

* A fully compromised iOS device (*kernel-level malware, jailbroken OS*)
* A malicious paired listener that the user explicitly approved
* Screen capture or camera attacks during QR pairing
* Physical coercion of the device owner

NovaKey makes **no claims** to defend against attackers who fully control the operating system or the user.

---

## 🔑 Local Secret Storage

* Secrets are stored **only on the device**
* Secrets are saved in the **iOS Keychain**
* Keychain entries are protected with:

  * Face ID / Touch ID / device passcode
  * `ThisDeviceOnly` access control
* Secrets are **never displayed in plaintext** after saving

If biometric authentication fails or is unavailable, secrets cannot be retrieved.

---

## 📋 Clipboard Handling

* Clipboard writes are **explicit user actions**
* Clipboard contents are marked as **local-only**
* Optional auto-clear timeout (*user configurable*)
* Clipboard is cleared on backgrounding **only if NovaKey wrote it**
* NovaKey will **not overwrite unrelated clipboard content**

This minimizes the risk of secrets persisting unintentionally.

---

## 🔗 Pairing Security

### Pairing Properties

* Pairing is **explicit and user-initiated**
* Pairing requires scanning a **NovaKey-specific QR code**
* Each pairing binds:

  * A unique device ID
  * A device-specific secret key
  * A specific host and port

### Protections

* Host and port mismatches are rejected
* Expired pairing tokens are rejected
* Pairing credentials are stored securely in the iOS Keychain
* Pairing data cannot be silently reused across hosts

NovaKey **does not auto-pair** with unknown listeners.

---

## 🔐 Cryptography Overview

NovaKey uses modern, well-reviewed cryptographic primitives:

* **Key exchange:** ML-KEM (Kyber768)
* **Encryption:** XChaCha20-Poly1305
* **Authentication:** Device-bound keys
* **Replay protection:** Nonces + freshness checks

Cryptographic operations are handled by a dedicated crypto module and validated before use.

NovaKey does **not** invent new cryptographic algorithms.

---

## 🚫 What NovaKey Does *Not* Do

NovaKey intentionally does **not**:

* Sync secrets to the cloud
* Transmit secrets automatically or in the background
* Allow silent pairing
* Log or collect secret values
* Claim to be “unhackable” or “military-grade”

All sensitive actions require **direct user intent**.

---

## 🧍 User Responsibility

Users are responsible for:

* Pairing only with listeners they trust
* Verifying the host and port during pairing
* Protecting their physical device
* Reviewing daemon-side configuration and permissions

NovaKey provides safeguards, but **trust boundaries matter**.

---

## 🐞 Vulnerability Reporting

If you discover a security issue:

📧 **Email:** [security@novakey.app](mailto:security@novakey.app)  
🔑 **My PGP Key** https://downloads.osbornepro.com/publickey.asc  
🔐 **Optional:** Encrypted reports are welcome  
⏱️ **Response:** We aim to acknowledge reports promptly  
  
Please do **not** file sensitive issues in public trackers.

---

## 📄 Disclosure Policy

* Confirmed vulnerabilities will be fixed as quickly as practical
* Users will be notified when updates address security issues
* Credit is given to responsible reporters (*upon request*)

---

## ✅ Summary

NovaKey’s iOS app is designed to:

* Keep secrets local and protected
* Require explicit user intent for every sensitive action
* Use modern, conservative cryptography
* Fail safely when trust assumptions are violated

Security is a **core design goal**, not an afterthought.
