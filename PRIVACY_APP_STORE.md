# 🛡️ App Store Privacy Disclosure

This document is a plain-English summary of NovaKey’s privacy posture.
Your official App Privacy answers in App Store Connect must match the app build you ship.

## Data Collection (Developer / Third Parties)

NovaKey does **not** collect personal data to a developer-controlled server and does not include third-party analytics or advertising SDKs.

NovaKey’s core behavior is peer-to-peer: when you choose **Send**, the app transmits the secret directly to a computer you explicitly paired with.

> Apple’s “collection” for privacy labels generally refers to data transmitted off-device in a way the developer and/or integrated third parties can access beyond real-time servicing.

## Data Stored on Device

- Secrets are stored locally on your device.
- Secrets are protected by the iOS Keychain.
- Secrets are marked `ThisDeviceOnly` where supported.
- No analytics, tracking identifiers, or advertising identifiers are used.

## Data Shared

- Secrets are transmitted **only** to computers you explicitly pair with.
- Transmission is end-to-end encrypted between the phone and the paired computer.
- No cloud storage is used.

## Tracking

NovaKey does not track users across apps or websites.
NovaKey does not share data with data brokers and does not use data for targeted advertising.

## Diagnostics

NovaKey does not upload logs to the developer.
The paired computer (NovaKey-Daemon) may generate local logs depending on its configuration.

Note: If you choose to rely on platform crash reporting that is visible in App Store Connect, you may need to disclose **Diagnostics → Crash Data** in App Privacy.

