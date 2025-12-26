# App Store Export Compliance – Encryption Summary (NovaKey)

This document is provided to support App Store Connect export compliance review.

---

## Does the app use encryption?
Yes. NovaKey uses encryption to protect communication between the iOS app and the
user’s paired computer.

---

## Is the encryption used for purposes other than authentication?
Yes. Encryption is used to protect the confidentiality and integrity of data
transmitted between paired devices.

---

## What type of encryption is used?
NovaKey uses standard, peer-reviewed cryptographic algorithms, including:

- Post-quantum key establishment (ML-KEM-768 / Kyber768)
- Key derivation using HKDF-SHA256
- Authenticated encryption using XChaCha20-Poly1305

---

## Is the encryption proprietary or custom?
No. NovaKey does not use proprietary or custom encryption algorithms. All
cryptographic algorithms used are publicly documented and widely reviewed.

---

## Does the app use encryption for data at rest?
NovaKey stores limited configuration and pairing information locally on the user’s
device using iOS system security features (such as the iOS Keychain). NovaKey does
not store user input content.

---

## Is any encrypted data or key material transmitted to servers?
No. NovaKey does not transmit encryption keys, user input, or encrypted payloads
to NovaKey servers.

---

## Does the app qualify for exemption under App Store export compliance?
Yes. NovaKey uses encryption solely for the purpose of securing user data and
communications and does not provide encryption as a general-purpose service.

---

