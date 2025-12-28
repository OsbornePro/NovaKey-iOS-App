//
//  VaultTransferViews.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct VaultTransferViews: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Export options
    @State private var protection: VaultProtection = .password
    @State private var cipher: VaultCipher = .aesGcm256
    @State private var password: String = ""
    @State private var confirmPassword: String = ""

    /// Match Settings screen: default true.
    @AppStorage("requireFreshBiometric") private var requireFreshBiometric: Bool = true

    // UI state
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportData: Data?
    @State private var importData: Data?
    @State private var showPasswordPrompt = false
    @State private var importPassword: String = ""
    @State private var exportCompleted = false
    @State private var importSelectionCompleted = false

    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert = false
    @State private var dismissAfterAlertOK = false

    private func resetSensitiveUI() {
        password = ""
        confirmPassword = ""
        importPassword = ""

        exportData = nil
        importData = nil

        // optional: also reset pickers if you want
        // protection = .password
        // cipher = .aesGcm256
    }

    private var passwordRequired: Bool { protection == .password && cipher != .none }
    private var passwordIsValid: Bool {
        if !passwordRequired { return true }
        let p = password.trimmingCharacters(in: .whitespacesAndNewlines)
        return !p.isEmpty && p == confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Export") {
                    Picker("Protection", selection: $protection) {
                        ForEach(VaultProtection.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    
                    Picker("Cipher", selection: $cipher) {
                        ForEach(VaultCipher.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .disabled(protection == .none)
                    
                    if protection == .password {
                        SecureField("Password", text: $password)
                        SecureField("Confirm Password", text: $confirmPassword)
                        
                        if !confirmPassword.isEmpty && password != confirmPassword {
                            Text("Passwords do not match.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    Toggle("Require Face ID during export", isOn: $requireFreshBiometric)
                    
                    Button("Export Vault…") { doExport() }
                        .disabled(!passwordIsValid)
                }
                
                Section("Import") {
                    Button("Import Vault…") { showingImporter = true }
                }
                
                Section {
                    Button("Done") { dismiss() }
                }
            }
            .navigationTitle("Import / Export")
            .fileExporter(
                isPresented: $showingExporter,
                document: exportData.map { VaultFileDocument(data: $0) },
                contentType: .json,
                defaultFilename: "novakey-vault.json"
            ) { result in
                switch result {
                case .success:
                    exportCompleted = true
                    resetSensitiveUI()
                    showInfo("Export complete", "Vault file saved.", dismissOnOK: true)
                case .failure(let err):
                    showInfo("Export failed", err.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let data = try Data(contentsOf: url)
                        importData = data
                        // Attempt import without password first; if password required we'll prompt.
                        doImport(password: nil)
                    } catch {
                        showInfo("Import failed", "Could not read file.")
                    }
                case .failure(let err):
                    showInfo("Import failed", err.localizedDescription)
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) {
                    if dismissAfterAlertOK {
                        dismissAfterAlertOK = false
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showPasswordPrompt) {
                NavigationStack {
                    Form {
                        Section("Password Required") {
                            SecureField("Password", text: $importPassword)
                        }
                    }
                    .navigationTitle("Decrypt Vault")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                importPassword = ""
                                showPasswordPrompt = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Import") {
                                let pwd = importPassword
                                importPassword = ""
                                showPasswordPrompt = false
                                doImport(password: pwd)
                            }
                            .disabled(importPassword.isEmpty)
                        }
                    }
                }
            }
        }
        .onChange(of: showingExporter) { _, isShowing in
            // When exporter sheet closes:
            if !isShowing {
                if !exportCompleted {
                    exportData = nil
                    password = ""
                    confirmPassword = ""
                }
                exportCompleted = false // reset for next time
            }
        }
        .onChange(of: showingImporter) { _, isShowing in
            // When importer sheet closes:
            if !isShowing {
                if !importSelectionCompleted {
                    importData = nil
                    importPassword = ""
                }
                importSelectionCompleted = false // reset for next time
            }
        }
        .onChange(of: protection) { _, newValue in
            // keep UI tidy when switching protection modes
            if newValue == .none {
                password = ""
                confirmPassword = ""
                cipher = .none
            }
        }
        .onChange(of: cipher) { _, newValue in
            if protection == .password && newValue == .none {
                password = ""
                confirmPassword = ""
            }
        }
    }
    // MARK: - Export

    private func doExport() {
        // Normalize options
        if protection == .none {
            cipher = .none
        } else if cipher == .none {
            cipher = .aesGcm256
        }

        if passwordRequired && !passwordIsValid {
            showInfo("Password mismatch", "Passwords must match to export a password-protected vault.")
            return
        }

        do {
            let data = try VaultTransfer.exportVault(
                modelContext: modelContext,
                protection: protection,
                cipher: cipher,
                password: (passwordRequired ? password : nil),
                requireFreshBiometric: requireFreshBiometric
            )
            exportData = data
            showingExporter = true
        } catch {
            showInfo("Export failed", error.localizedDescription)
        }
    }

    // MARK: - Import

    private func doImport(password: String?) {
        guard let data = importData else { return }

        do {
            let payload = try VaultTransfer.importVault(data: data, password: password)

            // Write into Keychain + SwiftData.
            // If a secret already exists (same UUID), we overwrite the keychain value and update metadata.
            for r in payload.secrets {
                let existing = fetchSecretItem(id: r.id)

                if let item = existing {
                    item.name = r.name
                    item.createdAt = r.createdAt
                    item.updatedAt = r.updatedAt
                    item.lastUsedAt = r.lastUsedAt
                } else {
                    let item = SecretItem(name: r.name)
                    item.id = r.id
                    item.createdAt = r.createdAt
                    item.updatedAt = r.updatedAt
                    item.lastUsedAt = r.lastUsedAt
                    modelContext.insert(item)
                }

                try KeyChainVault.shared.save(secret: r.secret, for: r.id)
            }

            try modelContext.save()
            resetSensitiveUI()
            showInfo("Import complete", "Imported \(payload.secrets.count) secret(s).", dismissOnOK: true)

        } catch let e as VaultTransferError {
            if case .passwordRequired = e {
                showPasswordPrompt = true
            } else {
                showInfo("Import failed", e.localizedDescription)
            }
        } catch {
            showInfo("Import failed", error.localizedDescription)
        }
    }

    private func fetchSecretItem(id: UUID) -> SecretItem? {
        let fetch = FetchDescriptor<SecretItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(fetch).first
    }

    private func showInfo(_ title: String, _ message: String, dismissOnOK: Bool = false) {
        alertTitle = title
        alertMessage = message
        dismissAfterAlertOK = dismissOnOK
        showAlert = true
    }
}

// MARK: - FileDocument wrapper

/// Minimal FileDocument so we can use fileExporter with raw Data.
struct VaultFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
