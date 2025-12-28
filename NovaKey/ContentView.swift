//
//  ContentView.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \SecretItem.updatedAt, order: .reverse) private var secrets: [SecretItem]
    @Query private var listeners: [PairedListener]

    private enum ActiveSheet: String, Identifiable {
        case add, listeners, settings, exportVault, importVault, about, help
        var id: String { rawValue }
    }

    @SceneStorage("ContentView.activeSheet") private var activeSheetRaw: String?
    @State private var activeSheet: ActiveSheet?

    @SceneStorage("ContentView.searchText") private var searchText: String = ""

    // Tech details UX
    @State private var pendingTechDetailsPrompt = false
    @State private var showTechDetails = false
    @State private var techDetailsTitle: String = "NovaKey"
    @State private var techDetailsBody: String = ""

    @State private var selectedSecret: SecretItem?
    @State private var showActions = false

    @State private var pendingDelete: SecretItem?
    @State private var showDeleteConfirm = false

    @State private var statusToast: String?
    @State private var privacyCover = false

    @AppStorage("clipboardTimeout") private var clipboardTimeoutRaw: String = ClipboardTimeout.s60.rawValue
    @AppStorage("requireFreshBiometric") private var requireFreshBiometric: Bool = true
    @AppStorage("autoApproveBeforeSend") private var autoApproveBeforeSend: Bool = true

    private let client = NovaKeyClient()

    private var clipboardTimeout: ClipboardTimeout {
        ClipboardTimeout(rawValue: clipboardTimeoutRaw) ?? .s60
    }

    private var filteredSecrets: [SecretItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return secrets }
        return secrets.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func setActiveSheet(_ sheet: ActiveSheet?) {
        activeSheet = sheet
        activeSheetRaw = sheet?.rawValue
    }
    private func armTarget(durationMs: Int) async {
        do {
            let targetSnapshot: (String) = try await MainActor.run {
                guard let target = listeners.first(where: { $0.isDefault }) else {
                    throw NSError(domain: "NovaKey", code: 2, userInfo: [NSLocalizedDescriptionKey: "No Send Target set"])
                }
                return (target.displayName)
            }

            guard let pairing = PairingManager.load() else {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    toast("Not paired with \(targetSnapshot)")
                }
                return
            }

            let resp = try await client.sendArm(pairing: pairing, durationMs: durationMs)
            try await ensureSuccess(resp, targetName: targetSnapshot, stage: "arm")

            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                toast("Armed \(targetSnapshot) for \(durationMs / 1000)s")
            }
        } catch {
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                toast("Arm failed: \(error.localizedDescription)")
                print("Arm failed:", error)
            }
        }
    }

    private func disarmTarget() async {
        do {
            let targetSnapshot: (String) = try await MainActor.run {
                guard let target = listeners.first(where: { $0.isDefault }) else {
                    throw NSError(domain: "NovaKey", code: 2, userInfo: [NSLocalizedDescriptionKey: "No Send Target set"])
                }
                return (target.displayName)
            }

            guard let pairing = PairingManager.load() else {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    toast("Not paired with \(targetSnapshot)")
                }
                return
            }

            let resp = try await client.sendDisarm(pairing: pairing)
            try await ensureSuccess(resp, targetName: targetSnapshot, stage: "disarm")

            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                toast("Disarmed \(targetSnapshot)")
            }
        } catch {
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                toast("Disarm failed: \(error.localizedDescription)")
                print("Disarm failed:", error)
            }
        }
    }

    var body: some View {
        NavigationStack {
            secretsList
                .navigationTitle("NovaKey")
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .toolbar { topToolbar }

                .confirmationDialog(
                    "Secret Actions",
                    isPresented: $showActions,
                    titleVisibility: .visible
                ) {
                    Button("Copy") { Task { await copySelected() } }
                    Button("Send") { Task { await sendSelected() } }

                    Divider()

                    Button("Arm Computer (15s)") { Task { await armTarget(durationMs: 15_000) } }
                    Button("Disarm Computer") { Task { await disarmTarget() } }

                    Divider()

                    Button("Delete", role: .destructive) {
                        pendingDelete = selectedSecret
                        showDeleteConfirm = true
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(selectedSecret?.name ?? "")
                }

                .alert("Delete this secret?",
                       isPresented: $showDeleteConfirm) {
                    Button("Delete", role: .destructive) {
                        if let item = pendingDelete { deleteSecret(item) }
                        pendingDelete = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingDelete = nil
                    }
                } message: {
                    Text("This cannot be undone.")
                }

                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .about:
                        AboutView()
                    case .help:
                        HelpView()
                    case .add:
                        AddSecretView()
                    case .listeners:
                        ListenersView()
                    case .settings:
                        SettingsView()
                    case .exportVault:
                        ExportVaultView()
                    case .importVault:
                        ImportVaultView()
                    }
                }

                .overlay(alignment: .bottom) { toastOverlay }
                .overlay { privacyOverlay }
        }
        .onAppear {
            if let raw = activeSheetRaw, let sheet = ActiveSheet(rawValue: raw) {
                activeSheet = sheet
            }
        }
        .onChange(of: activeSheet) { _, newValue in
            activeSheetRaw = newValue?.rawValue
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                withAnimation { privacyCover = false }
            case .inactive:
                break
            case .background:
                withAnimation { privacyCover = true }
                if clipboardTimeout != .never {
                    ClipboardManager.clearNowIfOwnedAndUnchanged()
                }
            default:
                break
            }
        }

        // Renamed to avoid collision with your existing TechnicalDetailsSheet type
        .sheet(isPresented: $showTechDetails) {
            TechDetailsSheet(title: techDetailsTitle, details: techDetailsBody)
        }
        .confirmationDialog(
            "Show technical details?",
            isPresented: $pendingTechDetailsPrompt,
            titleVisibility: .visible
        ) {
            Button("Show technical details") { showTechDetails = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This includes status codes and daemon messages. You can copy it.")
        }
    }

    // MARK: - Pieces

    private var secretsList: some View {
        SwiftUI.List {
            if filteredSecrets.isEmpty {
                SwiftUI.Section {
                    ContentUnavailableView(
                        secrets.isEmpty ? "No Secrets Yet" : "No Matches",
                        systemImage: "key.fill",
                        description: Text(
                            secrets.isEmpty
                            ? "Tap + to add a secret. NovaKey never displays secrets after saving."
                            : "Try a different search."
                        )
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                SwiftUI.Section("Secrets") {
                    ForEach(filteredSecrets) { item in
                        secretRow(item)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { setActiveSheet(.listeners) } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            .accessibilityLabel("Listeners")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Clear Clipboard Now", role: .destructive) {
                    Task { @MainActor in
                        ClipboardManager.clearNow()
                        toast("Clipboard cleared")
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
                Divider()
                Button("Export Vault") { setActiveSheet(.exportVault) }
                Button("Import Vault") { setActiveSheet(.importVault) }
                Divider()
                Button("Settings") { setActiveSheet(.settings) }
                Button("Help") { setActiveSheet(.help) }
                Button("About") { setActiveSheet(.about) }
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .accessibilityLabel("Settings Menu")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button { setActiveSheet(.add) } label: {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("Add Secret")
        }
    }

    private var toastOverlay: some View {
        Group {
            if let statusToast {
                Text(statusToast)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var privacyOverlay: some View {
        Group {
            if privacyCover {
                Rectangle()
                    .fill(.black)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 28, weight: .semibold))
                            Text("Locked")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                    )
                    .transition(.opacity)
            }
        }
    }

    private func secretRow(_ item: SecretItem) -> some View {
        Button {
            selectedSecret = item
            showActions = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                    Image(systemName: "key.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline)
                    Text(item.updatedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func toast(_ s: String) {
        withAnimation { statusToast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { statusToast = nil }
        }
    }

    @MainActor
    private func deleteSecret(_ item: SecretItem) {
        KeyChainVault.shared.deleteSecret(for: item.id)
        modelContext.delete(item)
        try? modelContext.save()
        toast("Deleted")
    }

    private func copySelected() async {
        let snapshot: (id: UUID, name: String)?
        let requireFresh = requireFreshBiometric
        let timeout = clipboardTimeout

        do {
            snapshot = await MainActor.run {
                guard let item = selectedSecret else { return nil }
                return (item.id, item.name)
            }
            guard let snapshot else { return }

            let secret = try KeyChainVault.shared.readSecret(
                for: snapshot.id,
                prompt: "Copy \(snapshot.name)",
                requireFreshBiometric: requireFresh
            )

            ClipboardManager.copyRawSensitive(secret, timeout: timeout)

            await MainActor.run {
                if let item = secrets.first(where: { $0.id == snapshot.id }) {
                    item.lastUsedAt = .now
                    item.updatedAt = .now
                    try? modelContext.save()
                }

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if let seconds = timeout.seconds {
                    toast("Copied (clears in \(Int(seconds))s)")
                } else {
                    toast("Copied (no auto-clear)")
                }
            }
        } catch {
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                toast("Copy failed")
            }
        }
    }

    private func sendSelected() async {
        let requireFresh = requireFreshBiometric
        let doApprove = autoApproveBeforeSend

        do {
            let secretSnapshot: (id: UUID, name: String) = try await MainActor.run {
                guard let item = selectedSecret else {
                    throw NSError(domain: "NovaKey", code: 1, userInfo: [NSLocalizedDescriptionKey: "No secret selected"])
                }
                return (item.id, item.name)
            }

            let targetSnapshot: (host: String, port: Int, name: String) = try await MainActor.run {
                guard let target = listeners.first(where: { $0.isDefault }) else {
                    throw NSError(domain: "NovaKey", code: 2, userInfo: [NSLocalizedDescriptionKey: "No Send Target set"])
                }
                return (target.host, target.port, target.displayName)
            }

            guard let pairing = PairingManager.load() else {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    toast("Not paired with \(targetSnapshot.name)")
                }
                return
            }

            let secret = try KeyChainVault.shared.readSecret(
                for: secretSnapshot.id,
                prompt: "Send \(secretSnapshot.name) to \(targetSnapshot.name)",
                requireFreshBiometric: requireFresh
            )

            if doApprove {
                let approveResp = try await client.sendApprove(pairing: pairing)
                try await ensureSuccess(approveResp, targetName: targetSnapshot.name, stage: "approve")
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            let injectResp: NovaKeyClient.ServerResponse
            do {
                let r = try await client.sendInject(secret: secret, pairing: pairing)
                try await ensureSuccess(r, targetName: targetSnapshot.name, stage: "inject")
                injectResp = r
            } catch {
                if doApprove {
                    let approveResp2 = try await client.sendApprove(pairing: pairing)
                    try await ensureSuccess(approveResp2, targetName: targetSnapshot.name, stage: "approve(retry)")
                    try? await Task.sleep(nanoseconds: 250_000_000)

                    let r2 = try await client.sendInject(secret: secret, pairing: pairing)
                    try await ensureSuccess(r2, targetName: targetSnapshot.name, stage: "inject(retry)")
                    injectResp = r2
                } else {
                    throw error
                }
            }

            await MainActor.run {
                if let item = secrets.first(where: { $0.id == secretSnapshot.id }) {
                    item.lastUsedAt = .now
                    item.updatedAt = .now
                    try? modelContext.save()
                }

                switch injectResp.status {
                case .ok:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    toast("Sent to \(targetSnapshot.name)")

                case .okClipboard:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    let msg = Self.clean(injectResp.message)
                    toast(msg.isEmpty ? "📋 Copied to clipboard on \(targetSnapshot.name)" : "📋 \(msg)")

                default:
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    toast("Send failed")
                }
            }

        } catch {
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                toast("Send failed: \(error.localizedDescription)")
                print("Send failed:", error)
            }
        }
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func friendlyStatusMessage(_ status: NovaKeyClient.Status, targetName: String) -> String {
        switch status {
        case .notArmed:      return "Computer isn’t armed. Arm NovaKey-Daemon, then try again."
        case .needsApprove:  return "Computer needs approval. Approve on the computer, then try again."
        case .notPaired:     return "Not paired with \(targetName). Re-pair and try again."
        case .badRequest:    return "Request rejected by the computer."
        case .badTimestamp:  return "Clock check failed. Ensure your phone and computer time are correct."
        case .replay:        return "Replay detected. Try sending again."
        case .rateLimit:     return "Rate limited by the computer. Wait a moment and try again."
        case .cryptoFail:    return "Secure channel failed. Re-pair with the computer and try again."
        case .internalError: return "Computer error. Try again (or check daemon logs)."
        case .ok, .okClipboard:
            return "Success"

        case .unknown:
            // Your enum already has a “catch-all” case, so use it.
            return "Computer returned status 0x\(String(format: "%02X", status.rawValue))."
        }
    }

    @MainActor
    private func offerTechnicalDetails(title: String, details: String) {
        techDetailsTitle = title
        techDetailsBody = details
        pendingTechDetailsPrompt = true
    }

    private func ensureSuccess(
        _ resp: NovaKeyClient.ServerResponse,
        targetName: String,
        stage: String
    ) async throws {
        if resp.status.isSuccess { return }

        let raw = Self.clean(resp.message)
        let detailBlock = """
        Stage: \(stage)
        Status: \(resp.status) (0x\(String(format: "%02X", resp.status.rawValue)))
        Message: \(raw.isEmpty ? "<empty>" : raw)
        Target: \(targetName)
        """

        print("NovaKey send failed\n\(detailBlock)")

        let friendly = Self.friendlyStatusMessage(resp.status, targetName: targetName)

        await MainActor.run {
            offerTechnicalDetails(title: "Send failed", details: detailBlock)
        }

        throw NSError(domain: "NovaKey", code: Int(resp.status.rawValue), userInfo: [
            NSLocalizedDescriptionKey: friendly
        ])
    }
}

// MARK: - Local tech-details sheet (renamed to avoid collisions)

private struct TechDetailsSheet: View {
    let title: String
    let details: String

    @Environment(\.dismiss) private var dismiss
    @State private var copiedToast = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Technical details")
                    .font(.headline)

                ScrollView {
                    Text(details)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if copiedToast {
                    Text("Copied")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = details
                        copiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            copiedToast = false
                        }
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
