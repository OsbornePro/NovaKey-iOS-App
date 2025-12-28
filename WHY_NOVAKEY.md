# Why NovaKey?

## The problem

Typing high-value secrets on a desktop keyboard can be risky:

- Keyloggers / malware
- Screen capture or remote desktop recording
- Shoulder surfing
- Clipboard leaks and “secure field” surprises

Beyond the technical risks, there’s a human problem:
- Strong master passwords are hard to memorize.
- Losing a master password can lock you out completely.
- Weak or reused master passwords become a single catastrophic failure point.

## The NovaKey goal

Make “use a strong secret” the easy option.

NovaKey is built so your most sensitive secrets can live on your phone and be used on your computer **only when you explicitly decide to send them**.

## How NovaKey approaches it

**Your phone becomes the secure keyboard.**

1. Secrets live only on your phone (protected by iOS Keychain).
2. You explicitly choose when to send.
3. Each send is authenticated, encrypted, and policy-checked.
4. The computer only receives the secret at the moment it is needed (to inject or copy locally).

## What makes NovaKey different

### 🔐 Strong cryptography
- Post-quantum KEM: ML-KEM-768
- Authenticated encryption: XChaCha20-Poly1305
- Replay + freshness protection

### 🧠 Human-in-the-loop safety
- Explicit “send now” action
- Optional arming (“push-to-type”)
- Optional Two-Man Mode (Approve → Inject)

### 🚫 No cloud, no tracking
- No accounts
- No analytics / telemetry
- No third-party servers required for core operation

### 📋 Safe, visible fallbacks
If the system cannot type into the focused field (Wayland, secure input, permissions, policy):
- NovaKey can fall back to copying to clipboard (when enabled)
- This outcome is explicit and user-visible, not silent

## Threat model philosophy

> Assume the desktop may be hostile.  
> Trust the phone’s secure storage.  
> Require clear user intent.

NovaKey is designed to reduce secret exposure even when the environment is imperfect.

