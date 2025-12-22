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

    // Navigation / sheets
    private enum ActiveSheet: String, Identifiable {
        case add, listeners, settings, exportVault, importVault
        var id: String { rawValue }
    }

    @State private var activeSheet: ActiveSheet?

    // Secret actions
    @State private var selectedSecret: SecretItem?
    @State private var showActions = false

    // Delete confirm
    @State private var pendingDelete: SecretItem?
    @State private var showDeleteConfirm = false

    // UI
    @State private var statusToast: String?
    @State private var searchText = ""
    @State private var privacyCover = false

    // Settings
    @AppStorage("clipboardTimeout") private var clipboardTimeoutRaw: String = ClipboardTimeout.s60.rawValue
    @AppStorage("requireFreshBiometric") private var requireFreshBiometric: Bool = true

    private var clipboardTimeout: ClipboardTimeout {
        ClipboardTimeout(rawValue: clipboardTimeoutRaw) ?? .s60
    }

    private var filteredSecrets: [SecretItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return secrets }
        return secrets.filter { $0.name.localizedCaseInsensitiveContains(q) }
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
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .add:
                        AddSecretView()
                    case .listeners:
                        ListenersView()
                    case .settings:
                        SettingsView()
                    case .exportVault:
                        ExportVaultView() // <-- shim view (or your real export UI)
                    case .importVault:
                        ImportVaultView() // <-- shim view (or your real import UI)
                    }
                }
                .overlay(alignment: .bottom) { toastOverlay }
                .overlay { privacyOverlay }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                withAnimation { privacyCover = false }
            case .inactive, .background:
                withAnimation { privacyCover = true }
                if clipboardTimeout != .never {
                    ClipboardManager.clearNow()
                }
            default:
                break
            }
        }
    }

    // MARK: - Pieces (helps compiler)

    private var secretsList: some View {
        List {
            if filteredSecrets.isEmpty {
                Section {
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
                Section("Secrets") {
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
            Button { activeSheet = .listeners } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            .accessibilityLabel("Listeners")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Settings") { activeSheet = .settings }

                Button("Clear Clipboard Now", role: .destructive) {
                    ClipboardManager.clearNow()
                    toast("Clipboard cleared")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }

                Divider()

                Button("Export Vault") { activeSheet = .exportVault }
                Button("Import Vault") { activeSheet = .importVault }
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .accessibilityLabel("Settings Menu")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button { activeSheet = .add } label: {
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

    private func toast(_ s: String) {
        withAnimation { statusToast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { statusToast = nil }
        }
    }

    private func deleteSecret(_ item: SecretItem) {
        KeyChainVault.shared.deleteSecret(for: item.id)
        modelContext.delete(item)
        try? modelContext.save()
        toast("Deleted")
    }

    private func copySelected() async {
        guard let item = selectedSecret else { return }
        do {
            let secret = try KeyChainVault.shared.readSecret(
                for: item.id,
                prompt: "Copy \(item.name)",
                requireFreshBiometric: requireFreshBiometric
            )

            ClipboardManager.copyRawSensitive(secret, timeout: clipboardTimeout)

            item.lastUsedAt = .now
            item.updatedAt = .now
            try? modelContext.save()

            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if let seconds = clipboardTimeout.seconds {
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
        // You said you'll wire Send later.
        await MainActor.run {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            toast("Send not wired yet")
        }
    }
}
