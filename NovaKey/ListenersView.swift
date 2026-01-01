//
//  ListenersView.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct ListenersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var proStore: ProStore

    @Query(sort: \PairedListener.displayName) private var listeners: [PairedListener]

    @AppStorage("listeners.add.name") private var name = ""
    @AppStorage("listeners.add.host") private var host = ""
    @AppStorage("listeners.add.portText") private var portText = "60768"
    @AppStorage("listeners.add.notes") private var notes = ""
    @AppStorage("listeners.add.makeSendTarget") private var makeSendTarget = false

    @State private var pairingFor: PairedListener?

    @State private var editing: PairedListener?
    @State private var editNameText: String = ""
    @State private var editNotesText: String = ""
    @State private var showEditSheet = false
    @State private var showLimitAlert = false
    @State private var showPaywall = false
    @State private var toastText: String?
    @State private var showToast = false

    var body: some View {
        NavigationStack {
            SwiftUI.List {
                SwiftUI.Section {
                    if listeners.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No listeners")
                                .font(.headline)
                            Text("Add a listener below, then pair it using the nvpair JSON blob (or scan the daemon QR).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(listeners) { l in
                            listenerRow(l)
                        }
                        .onDelete(perform: deleteOffsets)
                    }
                } header: {
                    Text("Paired Listeners")
                }

                SwiftUI.Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)

                    TextField("Host or IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)

                    TextField("Notes (optional)", text: $notes)
                        .textInputAutocapitalization(.words)

                    Toggle("Make Send Target", isOn: $makeSendTarget)

                    Button("Add") { addListener() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            Int(portText) == nil
                        )
                } header: {
                    Text("Add Listener")
                } footer: {
                    Text("“Send Target” is where secrets will be sent when you press Send in the main list.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Listeners")
        .alert("Limit reached", isPresented: $showLimitAlert) {
            Button("Unlock Pro") { showPaywall = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Free version allows only 1 listener. Unlock Pro for unlimited listeners.")
        }
        .sheet(isPresented: $showPaywall) { ProPaywallView() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $pairingFor) { l in
                PairingPasteSheet(listener: l) { result in
                    switch result {
                    case .saved:
                        toast("Paired with \(l.displayName)")
                    case .mismatch(let expected, let got):
                        toast("Pairing mismatch: expected \(expected), got \(got)")
                    case .failed:
                        toast("Pairing failed")
                    case .cancelled:
                        break
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditListenerSheet(
                    title: "Edit Listener",
                    initialName: editNameText,
                    initialNotes: editNotesText
                ) { newName, newNotes in
                    saveEdits(newName: newName, newNotes: newNotes)
                } onCancel: {
                    editing = nil
                }
            }
            .overlay(alignment: .bottom) {
                if showToast, let toastText {
                    Text(toastText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Row

    private func listenerRow(_ l: PairedListener) -> some View {
        let isPaired = (PairingManager.load(host: l.host, port: l.port) != nil)
        let notesTrimmed = l.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        return Button {
            if editMode?.wrappedValue.isEditing == true { return }
            setSendTarget(l)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(l.displayName)
                            .font(.headline)

                        if isPaired {
                            Label("Paired", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Not paired", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(l.host + ":" + String(l.port))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !notesTrimmed.isEmpty {
                        Text(notesTrimmed)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if l.isDefault {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Send Target")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .imageScale(.large)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Set as Send Target") { setSendTarget(l) }
            Button("Edit") { beginEdit(l) }

            Button(isPaired ? "Re-pair" : "Pair") {
                presentPairSheet(for: l)
            }

            Button("Debug: Check Paired") {
                let loaded = PairingManager.load(host: l.host, port: l.port)
                if loaded != nil {
                    toast("✅ Keychain has pairing for \(l.host):\(l.port)")
                } else {
                    toast("❌ No pairing in keychain for \(l.host):\(l.port)")
                }
            }

            Divider()

            Button("Delete", role: .destructive) { deleteOne(l) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { deleteOne(l) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                presentPairSheet(for: l)
            } label: {
                Label(isPaired ? "Re-pair" : "Pair", systemImage: "qrcode")
            }

            Button {
                setSendTarget(l)
            } label: {
                Label("Send Target", systemImage: "paperplane.fill")
            }
        }
    }

    private func presentPairSheet(for l: PairedListener) {
        pairingFor = l
    }

    // MARK: - Edit (name + notes only)

    private func beginEdit(_ listener: PairedListener) {
        editing = listener
        editNameText = listener.displayName
        editNotesText = listener.notes
        showEditSheet = true
    }

    private func saveEdits(newName: String, newNotes: String) {
        defer {
            editing = nil
            showEditSheet = false
        }

        let nameTrimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nameTrimmed.isEmpty else {
            toast("Name can’t be empty")
            return
        }

        guard let l = editing else { return }
        l.displayName = nameTrimmed
        l.notes = newNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        try? modelContext.save()
        toast("Saved")
    }

    // MARK: - Send Target

    private func setSendTarget(_ listener: PairedListener) {
        for l in listeners {
            l.isDefault = (l.id == listener.id)
        }
        try? modelContext.save()
        toast("Send Target: \(listener.displayName)")
    }

    // MARK: - Add / Delete

    private func addListener() {
        // Free tier: allow only 1 listener total.
        if !proStore.isProUnlocked && listeners.count >= 1 {
            toast("Free version allows 1 listener. Unlock Pro for unlimited.")
            A11yAnnounce.say("Free version allows one listener. Unlock Pro for unlimited.")
            presentLimitAlert()
            return
        }

        guard let port = Int(portText) else { return }

        let new = PairedListener(
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            isDefault: makeSendTarget,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if makeSendTarget {
            for l in listeners { l.isDefault = false }
        } else if listeners.contains(where: { $0.isDefault }) == false {
            new.isDefault = true
        }

        modelContext.insert(new)
        try? modelContext.save()

        name = ""
        host = ""
        portText = "60768"
        notes = ""
        makeSendTarget = false

        toast("Listener added")
    }

    private func deleteOffsets(_ offsets: IndexSet) {
        for idx in offsets {
            deleteOne(listeners[idx], showToast: false)
        }
        try? modelContext.save()
        ensureSendTargetExists()
        toast("Deleted")
    }

    private func deleteOne(_ listener: PairedListener, showToast: Bool = true) {
        let wasSendTarget = listener.isDefault

        // 1) Delete pairing only for this listener (DeviceID is global; don't reset here)
        PairingManager.resetPairing(host: listener.host, port: listener.port, resetDeviceID: false)

        // 2) Delete any in-progress pairing draft for this listener
        let draftKey = "pairing.json.draft.\(listener.host):\(listener.port)"
        UserDefaults.standard.removeObject(forKey: draftKey)


        // 3) Delete from model
        modelContext.delete(listener)
        try? modelContext.save()

        if wasSendTarget { ensureSendTargetExists() }
        if showToast { toast("Deleted \(listener.displayName)") }
    }

    private func ensureSendTargetExists() {
        let remaining = listeners
        guard !remaining.isEmpty else { return }

        if remaining.contains(where: { $0.isDefault }) == false {
            remaining[0].isDefault = true
            try? modelContext.save()
        }
    }

    private func presentLimitAlert() {
        showLimitAlert = true
        A11yAnnounce.say("Limit reached. Unlock Pro to add more listeners.")
    }

    // MARK: - Toast

    private func toast(_ s: String) {
        withAnimation {
            toastText = s
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                showToast = false
                toastText = nil
            }
        }
    }
}

// MARK: - Edit sheet

private struct EditListenerSheet: View {
    let title: String
    let initialName: String
    let initialNotes: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    @State private var name: String
    @State private var notes: String

    init(
        title: String,
        initialName: String,
        initialNotes: String,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.initialName = initialName
        self.initialNotes = initialNotes
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
        _notes = State(initialValue: initialNotes)
    }

    var body: some View {
        NavigationStack {
            SwiftUI.Form {
                SwiftUI.Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($focused)
                } header: {
                    Text("Name")
                }

                SwiftUI.Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Notes (optional)")
                } footer: {
                    Text("Notes are local only. Pairing/security settings are unchanged.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dismiss()
                        onSave(name, notes)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    focused = true
                }
            }
        }
    }
}

