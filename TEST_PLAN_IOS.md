# Test Plan — Pairing & Clipboard Edge Cases

This is a **QA-ready checklist** reviewers can follow.

---

## A. Pairing Tests

### A1. Happy Path

* Start daemon with no devices
* QR generated
* Scan QR
* Confirm host:port
* Pair succeeds
* Device stored

✅ Expected: success

---

### A2. QR Host Mismatch

* Scan QR from different daemon
* Confirm dialog shows mismatch
* User cancels

✅ Expected: no pairing, no network calls

---

### A3. Expired QR

* Wait past token TTL
* Scan QR

✅ Expected: clear error (*“QR expired”*)

---

### A4. Replay Pairing

* Reuse same QR after successful pairing

✅ Expected: pairing rejected

---

## B. Injection Tests

### B1. Direct Injection (*X11/macOS/Windows*)

* Armed
* Approved
* Inject into text field

✅ Expected: typed injection, StatusOK

---

### B2. Wayland Clipboard Fallback

* Linux Wayland
* Armed + approved
* Inject attempt fails
* Clipboard fallback enabled

✅ Expected:

* Clipboard set
* StatusOKClipboard
* App toast shows clipboard message

---

### B3. Clipboard Disabled

* Same as B2
* `allow_clipboard_on_inject_failure = false`

✅ Expected: injection fails, no clipboard

---

### B4. Not Armed

* Try send without arming

✅ Expected:

* StatusNotArmed
* No clipboard unless explicitly allowed

---

### B5. Two-Man Approval Missing

* Two-man enabled
* Inject without approve

✅ Expected:

* StatusNeedsApprove
* Optional clipboard if allowed

---

## C. UX Validation

* Clipboard success shows different icon/message
* Typed success shows “*Sent*”
* All failures show actionable messages
* No silent retries without user awareness

---
