//
//  ListenersView.swift
//  NovaKey
//
//  Replaces your existing ListenersView.swift
//
//  Features:
//  - “Send Target” (replaces confusing “Default” wording)
//  - Tap a listener row (when not editing) to set Send Target
//  - Shows pairing status (Paired / Not paired)
//  - Pair / Update pairing via pasting the nvpair JSON blob
//  - “Approve” action (for two-man mode) using NovaKeyClientV3
//  - Swipe-to-delete + multi-select delete in Edit mode
//

import SwiftUI
import SwiftData

struct ListenersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @Query(sort: \PairedListener.displayName) private var listeners: [PairedListener]

    // Multi-select delete
    @State private var selectedIDs = Set<PairedListener.ID>()

    @State private var showBulkDeleteConfirm = false

    // Add listener form
    @State private var name = ""
    @State private var host = ""
    @State private var portText = "60768"
    @State private var makeSendTarget = false

    // Pairing sheet
    @State private var pairingFor: PairedListener?
    @State private var showPairingSheet = false

    // Approve action feedback
    @State private var toastText: String?
    @State private var showToast = false

    private let client = NovaKeyClientV3()

    var body: some View {
        NavigationStack {
            SwiftUI.List(selection: $selectedIDs) {

                Section("Paired Listeners") {
                    if listeners.isEmpty {
                        ContentUnavailableView(
                            "No listeners",
                            systemImage: "antenna.radiowaves.left.and.right",
                            description: Text("Add a listener below, then pair it using the nvpair JSON blob.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(listeners) { l in
                            listenerRow(l)
                                .tag(l.id)
                        }
                        .onDelete(perform: deleteOffsets)
                    }
                }

                Section("Add Listener") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)

                    TextField("Host or IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)

                    Toggle("Make Send Target", isOn: $makeSendTarget)

                    Button("Add") { addListener() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            Int(portText) == nil
                        )
                } footer: {
                    Text("“Send Target” is where secrets will be sent when you press **Send** in the main list.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Listeners")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .bottomBar) {
                    if editMode?.wrappedValue.isEditing == true, !selectedIDs.isEmpty {
                        Button(role: .destructive) {
                            showBulkDeleteConfirm = true
                        } label: {
                            Label("Delete (\(selectedIDs.count))", systemImage: "trash")
                        }
                    }
                }
            }
            .alert("Delete listeners?",
                   isPresented: $showBulkDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteSelected() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove \(selectedIDs.count) listener(s) from your phone.")
            }
            .sheet(isPresented: $showPairingSheet) {
                if let l = pairingFor {
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
                } else {
                    Text("No listener selected")
                        .padding()
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

        return Button {
            // When editing, allow selection; don’t hijack taps.
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

                    Text("\(l.host):\(l.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            Button(isPaired ? "Update Pairing" : "Pair") {
                pairingFor = l
                showPairingSheet = true
            }

            Button("Approve (two-man mode)") {
                Task { await approve(for: l) }
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
                pairingFor = l
                showPairingSheet = true
            } label: {
                Label(isPaired ? "Update" : "Pair", systemImage: "qrcode")
            }
            Button {
                setSendTarget(l)
            } label: {
                Label("Send Target", systemImage: "paperplane.fill")
            }
        }
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
        guard let port = Int(portText) else { return }

        let new = PairedListener(
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            isDefault: makeSendTarget
        )

        // If making send target, clear others
        if makeSendTarget {
            for l in listeners { l.isDefault = false }
        } else if listeners.contains(where: { $0.isDefault }) == false {
            // If this is the first listener ever, make it the send target.
            new.isDefault = true
        }

        modelContext.insert(new)
        try? modelContext.save()

        name = ""
        host = ""
        portText = "60768"
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

        modelContext.delete(listener)
        try? modelContext.save()

        if wasSendTarget {
            ensureSendTargetExists()
        }

        if showToast {
            toast("Deleted \(listener.displayName)")
        }
    }

    private func deleteSelected() {
        let doomed = listeners.filter { selectedIDs.contains($0.id) }
        let deletedSendTarget = doomed.contains(where: { $0.isDefault })

        for l in doomed { modelContext.delete(l) }
        try? modelContext.save()

        selectedIDs.removeAll()
        editMode?.wrappedValue = .inactive

        if deletedSendTarget {
            ensureSendTargetExists()
        }

        toast("Deleted selected")
    }

    private func ensureSendTargetExists() {
        // After deletes, make sure exactly one send target exists if any listeners remain.
        let remaining = listeners
        guard !remaining.isEmpty else { return }

        if remaining.contains(where: { $0.isDefault }) == false {
            remaining[0].isDefault = true
            try? modelContext.save()
        }
    }

    // MARK: - Approve

    private func approve(for listener: PairedListener) async {
        guard let pairing = PairingManager.load(host: listener.host, port: listener.port) else {
            await MainActor.run { toast("Not paired with \(listener.displayName)") }
            return
        }

        do {
            try await client.sendApprove(pairing: pairing)
            await MainActor.run { toast("Approved: \(listener.displayName)") }
        } catch {
            await MainActor.run { toast("Approve failed") }
        }
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

// MARK: - Pairing paste sheet

private struct PairingPasteSheet: View {
    enum Result {
        case saved
        case mismatch(expected: String, got: String)
        case failed
        case cancelled
    }

    let listener: PairedListener
    let onDone: (Result) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var jsonText: String = ""
    @State private var errorText: String?
    @State private var showMismatchAlert = false
    @State private var mismatchExpected = ""
    @State private var mismatchGot = ""

    var body: some View {
        NavigationStack {
            SwiftUI.Form {
                Section("Pairing JSON (from nvpair)") {
                    TextEditor(text: $jsonText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 220)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Paste the pairing blob JSON. Treat it as a secret.")
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button("Save Pairing") { save() }
                        .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Pair \(listener.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDone(.cancelled)
                    }
                }
            }
            .alert("Server address mismatch",
                   isPresented: $showMismatchAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Listener is \(mismatchExpected) but pairing blob is \(mismatchGot).\n\nCreate/update a listener that matches the pairing blob’s server_addr, then pair again.")
            }
        }
    }

    private func save() {
        do {
            let record = try PairingManager.parsePairingJSON(jsonText)

            let expected = "\(listener.host):\(listener.port)"
            let got = "\(record.serverHost):\(record.serverPort)"

            guard expected == got else {
                mismatchExpected = expected
                mismatchGot = got
                showMismatchAlert = true
                onDone(.mismatch(expected: expected, got: got))
                return
            }

            try PairingManager.save(record)
            dismiss()
            onDone(.saved)
        } catch {
            errorText = error.localizedDescription
            onDone(.failed)
        }
    }
}
