//
//  AddSecretView.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//
import SwiftUI
import SwiftData

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
                }

                Section("Secret") {
                    TextField("Enter secret", text: $secret)
                    TextField("Confirm secret", text: $confirm)
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
