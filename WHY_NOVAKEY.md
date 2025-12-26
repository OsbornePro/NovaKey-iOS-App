# Why NovaKey?

## The Problem

I could say typing secrets on a keyboard is risky because of:

* Keyloggers
* Screen capture malware
* Remote desktop recording
* Shoulder surfing
* Clipboard leaks

Beyond these technical risks, the real pain point is human:

- Memorizing strong passwords is exhausting.
- One forgotten master password locks you out of every other credential.
- Weak or reused master passwords become the single point of failure for the whole vault.


## The NovaKey Goal

Never memorize a password again.
We want a solution where the master secret is stored securely, offline, and outside the attack surface of everyday computing.
Avoiding keyloggers is just an added security bonus to justify this application.
  
## Why NovaKey Solves It

- Zero‑knowledge storage: NovaKey holds the master password in a hardware‑isolated enclave, never exposing it to the OS or network.
- Resistant to keyloggers, screen capture, clipboard theft, and shoulder surfing because the secret never leaves the device in plaintext.
- Single‑click retrieval: Unlock your password manager with a biometric or PIN, eliminating the mental load of remembering a complex master phrase.
- Backup‑ready: Encrypted backups let you recover the master secret without re‑creating it, preserving both security and convenience.

In short, NovaKey removes the weakest link—human memory—from the password‑management chain while defending against the most common credential‑theft vectors.

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
