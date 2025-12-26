# NovaKey Security Review Response Template

Thank you for reviewing NovaKey. Below are responses to common security and encryption questions.

---

## Does the app use encryption?
Yes. NovaKey encrypts communication between the iOS app and the paired computer using standard, peer-reviewed cryptographic algorithms.

---

## What encryption algorithms are used?
- **Post-quantum key establishment:** ML-KEM-768 (Kyber768)
- **Key derivation:** HKDF-SHA256 (domain-separated)
- **Authenticated encryption:** XChaCha20-Poly1305

---

## Where are encryption keys stored?
Encryption keys are generated and stored locally on user-controlled devices.  
NovaKey does **not** upload encryption keys to servers and does **not** use cloud-based key escrow.

---

## Does NovaKey collect or store user input?
No. NovaKey does not collect, store, or log typed input or clipboard contents.  
Input exists only transiently in memory for delivery to the paired device.

---

## How is device trust established?
Trust is established through explicit user approval during pairing.  
Devices must be allow-listed locally before they can send input.

---

## How are replay or tampering attacks prevented?
NovaKey uses authenticated encryption and enforces per-device nonce replay protection.  
Tampered or replayed messages are rejected.

---

## What threats are out of scope?
NovaKey does not attempt to protect against:
- A fully compromised host operating system
- Malicious kernel drivers
- Physical device compromise

These limitations are documented and intentional.

---

## Is custom or proprietary cryptography used?
No. NovaKey uses established, peer-reviewed cryptographic algorithms and libraries.

