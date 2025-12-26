# 🧪 NovaKey Security Test Plan
This test plan validates the security and cryptographic guarantees described in:

- [Crypto Appendix](CRYPTO_APPENDIX.md)
- [Crypto Traceability (iOS)](CRYPTO_TRACEABILITY.md)
- [Crypto Traceability (Daemon)](CRYPTO_TRACEABILITY_DAEMON.md)


This document maps NovaKey’s security claims to automated tests.

> **Navigation**
>
> - 🔐 [Crypto Audit Appendix (Combined, PDF)](NovaKey_Crypto_Audit_Appendix_Combined.pdf)
> - 🧠 [Threat Model Diagram (PDF)](NovaKey_Threat_Model_Diagram.pdf)
> - 📋 [iOS Crypto Traceability](CRYPTO_TRACEABILITY.md)
> - 🖥️ [Daemon Crypto Traceability](CRYPTO_TRACEABILITY_DAEMON.md)
> - 🧪 [Security Test Plan](SECURITY_TEST_PLAN.md)

---

## Test Categories

### Unit Tests
- Pairing parsing
- Crypto framing
- Replay detection

### Integration Tests
- QR pairing flow
- Approval + injection sequencing

### UI Tests
- Biometric prompts
- Pair confirmation dialogs

---

## Required Tests

| Test | Purpose |
|----|--------|
| PairingManagerTests | Host mismatch rejection |
| PairQRDecodeTests | QR expiration |
| ClipboardManagerTests | Auto-clear behavior |
| ClientStatusTests | `.okClipboard` success |
| VaultAuthTests | Biometric enforcement |

---

## Regression Policy

Any change touching:
- pairing
- cryptography
- clipboard
- approval logic

**must include tests** or be rejected.

---

## Manual Test Checklist

- Wayland clipboard fallback
- Pairing wrong host
- Clipboard timeout expiration
- Approval expiry

---

**Reviewer References**
- [Crypto Audit Appendix (Combined, PDF)](NovaKey_Crypto_Audit_Appendix_Combined.pdf)
- [Threat Model Diagram](NovaKey_Threat_Model_Diagram.pdf)

