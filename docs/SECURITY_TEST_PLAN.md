# 🧪 NovaKey Security Test Plan

This document maps NovaKey’s security claims to automated tests.

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

