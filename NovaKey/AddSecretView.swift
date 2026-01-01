//
//  AddSecretView.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import SwiftUI
import SwiftData
import UIKit

struct AddSecretView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var proStore: ProStore
    @Query private var secrets: [SecretItem]

    // Persist drafts across leaving app & returning (scene-based persistence)
    @SceneStorage("AddSecret.name") private var name: String = ""
    @SceneStorage("AddSecret.secret") private var secret: String = ""
    @SceneStorage("AddSecret.confirm") private var confirm: String = ""

    @State private var errorMessage: String?
    @State private var showLimitAlert: Bool = false
    @State private var showPaywall: Bool = false
    @available(iOS 16.0, *)
    private func pasteButton(assign: @escaping (String) -> Void) -> some View {
        PasteButton(payloadType: Data.self) { items in
            // items are Data blobs; try to decode as UTF-8
            if let d = items.first, let s = String(data: d, encoding: .utf8), !s.isEmpty {
                errorMessage = nil
                assign(s)
            } else {
                errorMessage = "Clipboard doesn’t contain plain text that iOS can paste here."
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Email Master", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Secret") {
                    HStack(spacing: 10) {
                        SecureField("Enter secret", text: $secret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if #available(iOS 16.0, *) {
                            pasteButton { secret = $0 }
                        } else {
                            Button { paste(into: .secret) } label: {
                                Image(systemName: "doc.on.clipboard")
                                .a11yIconButton(label: "Paste from Clipboard", hint: "Pastes text from the system clipboard.")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack(spacing: 10) {
                        SecureField("Confirm secret", text: $confirm)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if #available(iOS 16.0, *) {
                            pasteButton { confirm = $0 }
                        } else {
                            Button { paste(into: .confirm) } label: {
                                Image(systemName: "doc.on.clipboard")
                                .a11yIconButton(label: "Paste from Clipboard", hint: "Pastes text from the system clipboard.")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .onAppear {
                    let pb = UIPasteboard.general
                    print("PASTE DEBUG onAppear hasStrings:", pb.hasStrings,
                          "string len:", pb.string?.count ?? -1,
                          "types:", pb.types)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                Section {
                    Button("Save") { save() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            secret.isEmpty ||
                            secret != confirm
                        )
                }
            }
            .navigationTitle("New Secret")
            .alert("Limit reached", isPresented: $showLimitAlert) {
                Button("Unlock Pro") { showPaywall = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Free version allows only 1 secret. Unlock Pro for unlimited secrets.")
            }
            .sheet(isPresented: $showPaywall) { ProPaywallView() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearDraft()
                        dismiss()
                    }
                }
            }
        }
    }

    private enum PasteTarget { case secret, confirm }

    private func paste(into target: PasteTarget) {
        errorMessage = nil
        let pb = UIPasteboard.general

        // Debug if you want:
        // print("Pasteboard hasStrings:", pb.hasStrings, "changeCount:", pb.changeCount)

        guard pb.hasStrings else {
            errorMessage = "Paste blocked by iOS. Go to Settings and allow “Paste from Other Apps” for NovaKey (or reset Location & Privacy)."
            return
        }

        guard let s = pb.string, !s.isEmpty else {
            errorMessage = "Clipboard is empty."
            return
        }

        switch target {
        case .secret:
            secret = s
        case .confirm:
            confirm = s
        }
    }

    private func save() {
        // Free tier: allow only 1 secret total.
        if !proStore.isProUnlocked && secrets.count >= 1 {
            errorMessage = "Free version allows 1 secret. Unlock Pro for unlimited."
            A11yAnnounce.say("Limit reached. Free version allows one secret. Unlock Pro for unlimited.")
            showLimitAlert = true
            return
        }

        guard secret == confirm else {
            errorMessage = "Secrets do not match"
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = SecretItem(name: trimmedName)

        do {
            try KeyChainVault.shared.save(secret: secret, for: item.id)
            modelContext.insert(item)
            try modelContext.save()

            // Clear persisted draft after successful save
            clearDraft()
            dismiss()
        } catch {
            errorMessage = "Failed to save to Keychain"
        }
    }

    private func clearDraft() {
        name = ""
        secret = ""
        confirm = ""
        errorMessage = nil
    }
}