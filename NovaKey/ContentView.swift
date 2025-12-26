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

    // Persist which sheet is open across app switches / scene recreation
    @SceneStorage("ContentView.activeSheet") private var activeSheetRaw: String?
    @State private var activeSheet: ActiveSheet?

    // Persist search text (optional)
    @SceneStorage("ContentView.searchText") private var searchText: String = ""

    @State private var selectedSecret: SecretItem?
    @State private var showActions = false

    @State private var pendingDelete: SecretItem?
    @State private var showDeleteConfirm = false

    @State private var statusToast: String?
    @State private var privacyCover = false

    @AppStorage("clipboardTimeout") private var clipboardTimeoutRaw: String = ClipboardTimeout.s60.rawValue
    @AppStorage("requireFreshBiometric") private var requireFreshBiometric: Bool = true
    @AppStorage("autoApproveBeforeSend") private var autoApproveBeforeSend: Bool = true

    private let client = NovaKeyClientV3()

    private var clipboardTimeout: ClipboardTimeout {
        ClipboardTimeout(rawValue: clipboardTimeoutRaw) ?? .s60
    }

    private var filteredSecrets: [SecretItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return secrets }
        return secrets.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    // keep these in sync
    private func setActiveSheet(_ sheet: ActiveSheet?) {
        activeSheet = sheet
        activeSheetRaw = sheet?.rawValue
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

                // Only ONE sheet modifier
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
            // restore persisted sheet (if any)
            if let raw = activeSheetRaw, let sheet = ActiveSheet(rawValue: raw) {
                activeSheet = sheet
            }
        }
        .onChange(of: activeSheet) { _, newValue in
            // keep persisted value updated
            activeSheetRaw = newValue?.rawValue
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                withAnimation { privacyCover = false }

            case .inactive:
                // Don't lock on inactive — this happens for FaceID/passcode/paste prompts.
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
            Button {
                setActiveSheet(.listeners)
            } label: {
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

    // MARK: - Row

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
        .contextMenu {
            Button("Copy") {
                selectedSecret = item
                Task { await copySelected() }
            }
            Button("Send") {
                selectedSecret = item
                Task { await sendSelected() }
            }
            Divider()
            Button("Delete", role: .destructive) {
                pendingDelete = item
                showDeleteConfirm = true
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingDelete = item
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

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
        let secretSnapshot: (id: UUID, name: String)?
        let targetSnapshot: (host: String, port: Int, name: String)?
        let requireFresh = requireFreshBiometric
        let doApprove = autoApproveBeforeSend
    
        do {
            secretSnapshot = await MainActor.run {
                guard let item = selectedSecret else { return nil }
                return (item.id, item.name)
            }
            guard let secretSnapshot else { return }
    
            targetSnapshot = await MainActor.run {
                guard let target = listeners.first(where: { $0.isDefault }) else { return nil }
                return (target.host, target.port, target.displayName)
            }
            guard let targetSnapshot else {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    toast("No Send Target set")
                }
                return
            }
    
            guard let pairing = PairingManager.load(host: targetSnapshot.host, port: targetSnapshot.port) else {
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
                _ = try await client.sendApprove(pairing: pairing)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
    
            let resp: NovaKeyClientV3.ServerResponse
            do {
                resp = try await client.sendInject(secret: secret, pairing: pairing)
            } catch {
                if doApprove {
                    _ = try await client.sendApprove(pairing: pairing)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    resp = try await client.sendInject(secret: secret, pairing: pairing)
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
    
                UINotificationFeedbackGenerator().notificationOccurred(.success)
    
                // ✅ UX: show daemon message on clipboard-success if provided
                if resp.status == .okClipboard {
                    let m = resp.message.trimmingCharacters(in: .whitespacesAndNewlines)
                    toast(m.isEmpty ? "Copied to clipboard on \(targetSnapshot.name)" : m)
                } else {
                    toast("Sent to \(targetSnapshot.name)")
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
}
