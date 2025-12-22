//
//  NovaKeyApp.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import SwiftUI
import SwiftData
import LocalAuthentication

@main
struct NovaKeyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // Theme
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    private var appearanceMode: AppearanceMode { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }

    // Clipboard (optional: clear on background unless Never)
    @AppStorage("clipboardTimeout") private var clipboardTimeoutRaw: String = ClipboardTimeout.s60.rawValue
    private var clipboardTimeout: ClipboardTimeout { ClipboardTimeout(rawValue: clipboardTimeoutRaw) ?? .s60 }

    @StateObject private var appLock = AppLock()

    var body: some Scene {
        WindowGroup {
            AppGateView()
                .environmentObject(appLock)
                .preferredColorScheme(appearanceMode.colorScheme)
                .task {
                    // Try to unlock on cold launch
                    await appLock.unlockIfNeeded()
                }
        }
        // Keep LocalAccount in container to avoid SwiftData migration headaches.
        // You can remove it later if you reset the store (delete the app from simulator/device).
        .modelContainer(for: [SecretItem.self, PairedListener.self, LocalAccount.self])
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task { await appLock.unlockIfNeeded() }

            case .inactive, .background:
                // Lock immediately when leaving the app
                appLock.lock()

                // Optional: clear clipboard when backgrounding unless Never
                if clipboardTimeout != .never {
                    ClipboardManager.clearNow()
                }

            default:
                break
            }
        }
    }
}

private struct AppGateView: View {
    @EnvironmentObject private var appLock: AppLock

    var body: some View {
        if appLock.isUnlocked {
            ContentView()
        } else {
            LockedView {
                Task { await appLock.unlockIfNeeded(forcePrompt: true) }
            }
        }
    }
}

private struct LockedView: View {
    let unlockAction: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .semibold))
                Text("NovaKey Locked")
                    .font(.headline)

                Button {
                    unlockAction()
                } label: {
                    Label("Unlock with Face ID", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
        }
    }
}

@MainActor
final class AppLock: ObservableObject {
    @Published var isUnlocked: Bool = false

    func lock() {
        isUnlocked = false
    }

    func unlockIfNeeded(forcePrompt: Bool = false) async {
        if isUnlocked && !forcePrompt { return }
        _ = await unlock(forcePrompt: forcePrompt)
    }

    private func unlock(forcePrompt: Bool) async -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = false

        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication // Face ID with passcode fallback (recommended)

        guard context.canEvaluatePolicy(policy, error: &error) else {
            // If device has no biometrics/passcode configured, fail closed (stay locked)
            isUnlocked = false
            return false
        }

        do {
            let ok = try await context.evaluatePolicy(
                policy,
                localizedReason: "Unlock NovaKey"
            )
            isUnlocked = ok
            return ok
        } catch {
            isUnlocked = false
            return false
        }
    }
}
