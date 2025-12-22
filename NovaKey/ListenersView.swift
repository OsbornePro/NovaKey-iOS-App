//
//  ListenersView.swift
//  NovaKey
//

import SwiftUI
import SwiftData

struct ListenersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @Query(sort: \PairedListener.displayName) private var listeners: [PairedListener]

    // Add listener form
    @State private var name = ""
    @State private var host = ""
    @State private var portText = "60768"
    @State private var makeSendTarget = false

    // Pairing sheet
    @State private var pairingFor: PairedListener?
    @State private var showPairingSheet = false

    // Toast
    @State private var toastText: String?
    @State private var showToast = false

    private let client = NovaKeyClientV3()

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
                            Text("Add a listener below, then pair it using the nvpair JSON blob.")
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

                    Toggle("Make Send Target", isOn: $makeSendTarget)

                    Button("Add") { addListener() }
                        .disabled(
                            name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty ||
                            host.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty ||
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
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
            // When editing, don't hijack taps.
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
            displayName: name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            host: host.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            port: port,
            isDefault: makeSendTarget
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

    // MARK: - Approve

    private func approve(for listener: PairedListener) async {
        guard let pairing = PairingManager.load(host: listener.host, port: listener.port) else {
            await MainActor.run { toast("Not paired with \(listener.displayName)") }
            return
        }

        do {
            _ = try await client.sendApprove(pairing: pairing)
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
    @FocusState private var editorFocused: Bool

    @State private var jsonText: String = ""
    @State private var errorText: String?
    @State private var showMismatchAlert = false
    @State private var mismatchExpected = ""
    @State private var mismatchGot = ""

    var body: some View {
        NavigationStack {
            SwiftUI.Form {
                SwiftUI.Section {
                    TextEditor(text: $jsonText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 260)                 // a bit taller
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($editorFocused)
                        .scrollContentBackground(.hidden)      // nicer on iOS 16+
                } header: {
                    Text("Pairing JSON (from nvpair)")
                } footer: {
                    Text("Paste the pairing blob JSON. Treat it as a secret.")
                }

                if let errorText {
                    SwiftUI.Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Pair \(listener.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Always reachable buttons (NOT covered by keyboard)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDone(.cancelled)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(jsonText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
                }

                // Keyboard toolbar to dismiss keyboard
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
            .alert("Server address mismatch", isPresented: $showMismatchAlert) {
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
