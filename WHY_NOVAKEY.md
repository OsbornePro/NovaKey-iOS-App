# Why NovaKey

## The Problem

Typing secrets on a keyboard is risky:

* Keyloggers
* Screen capture malware
* Remote desktop recording
* Shoulder surfing
* Clipboard leaks

---

## NovaKey’s Approach

**Your phone becomes the secure keyboard.**

1. Secrets live only on your phone
2. You explicitly choose when to send
3. The desktop never learns the secret until the moment of use
4. Every send is authenticated, encrypted, and policy-checked

---

## What Makes NovaKey Different

### 🔐 Strong Cryptography

* Post-quantum secure (ML-KEM-768)
* Authenticated encryption (XChaCha20-Poly1305)
* Replay and freshness protection

### 🧠 Human-in-the-Loop Security

* Explicit approval for every send
* Optional biometric freshness
* Optional two-man approval on desktop

### 🚫 No Cloud, No Tracking

* No accounts
* No analytics
* No telemetry
* No third-party servers

### 📋 Safe Fallbacks

* If injection isn’t possible (Wayland, secure fields)
* NovaKey falls back to clipboard **with clear user visibility**
* No silent downgrade

---

## Threat Model Philosophy

> **Assume the desktop is compromised.
> Trust the phone.
> Require intent.**

NovaKey is designed to reduce exposure even when the environment is hostile.

---
