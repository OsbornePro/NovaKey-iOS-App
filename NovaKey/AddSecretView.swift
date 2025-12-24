//
//  AddSecretView.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import SwiftUI
import UIKit   // ✅ needed for UIPasteboard

struct AddSecretView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var secret = ""
    @State private var confirm = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Email Master", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Secret") {
                    HStack {
                        SecureField("Enter secret", text: $secret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            paste(into: .secret)
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Paste secret")
                    }

                    HStack {
                        SecureField("Confirm secret", text: $confirm)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            paste(into: .confirm)
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Paste confirm secret")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                Section {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || secret.isEmpty || secret != confirm)
                } footer: {
                    Text("After saving, NovaKey will never display the secret again. Copy/Send will require Face ID / passcode.")
                }
            }
            .navigationTitle("New Secret")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private enum PasteTarget { case secret, confirm }

    private func paste(into target: PasteTarget) {
        errorMessage = nil
        let pb = UIPasteboard.general

        print("Pasteboard hasStrings:", pb.hasStrings, "changeCount:", pb.changeCount)

        guard pb.hasStrings else {
            errorMessage = "Paste blocked by iOS. Go to Settings and allow “Paste from Other Apps” for NovaKey (or reset Location & Privacy)."
            return
        }

        guard let s = pb.string, !s.isEmpty else {
            errorMessage = "Clipboard is empty."
            return
        }

        switch target {
        case .secret:  secret = s
        case .confirm: confirm = s
        }
    }

    private func save() {
        guard secret == confirm else { errorMessage = "Secrets do not match"; return }
        let item = SecretItem(name: name)
        do {
            try KeyChainVault.shared.save(secret: secret, for: item.id)
            modelContext.insert(item)
            try modelContext.save()
            secret = ""
            confirm = ""
            dismiss()
        } catch {
            errorMessage = "Failed to save to Keychain"
        }
    }
}
