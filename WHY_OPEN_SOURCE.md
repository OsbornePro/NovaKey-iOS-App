# Why Open Source

NovaKey is built around a simple promise: **your secrets should not require trust in a vendor-operated cloud**.

Open-sourcing NovaKey components helps users and reviewers verify that promise.

## What open source buys you

### Verifiable security posture
- You can inspect what the app and daemon do with secrets.
- The protocol, crypto choices, and security checks are reviewable.
- Claims like “no analytics” and “no cloud dependency” are auditable.

### Supply-chain transparency
Open source doesn’t magically prevent supply-chain risk, but it makes it easier to:
- detect unexpected dependencies or network calls,
- review changes across releases,
- reproduce builds and compare artifacts (when you choose to support that).

### Trust without accounts
NovaKey is designed to work without user accounts or vendor servers. Open source reinforces that:
- pairing is local,
- transport is direct to your paired computer,
- secrets are not uploaded to a third party by design.

## What open source does *not* guarantee
- It does not prevent compromise of your phone or computer.
- It does not make a malicious binary safe.
- It does not replace good operational hygiene (OS updates, permissions, etc.).

Open source is one layer: **auditability and verifiable intent**.

## Commercial note
NovaKey may include paid components (for example, an App Store iOS client).
Selling the app is compatible with open source: users pay for convenience, polish, and ongoing maintenance — while still being able to verify what the software does.

