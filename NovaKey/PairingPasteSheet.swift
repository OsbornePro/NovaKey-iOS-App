//
//  PairingPasteSheet.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/26/25.
//

import SwiftUI
import VisionKit

struct PairingPasteSheet: View {
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

    private let draftKey: String
    @AppStorage private var jsonText: String

    @State private var errorText: String?
    @State private var showMismatchAlert = false
    @State private var mismatchExpected = ""
    @State private var mismatchGot = ""

    @State private var showQRScanner = false

    // pairing confirmation before any network calls
    @State private var pendingLink: PairBootstrapLink?
    @State private var showPairConfirmAlert = false
    @State private var pendingConfirmTitle = "Confirm Pairing"
    @State private var pendingConfirmMessage = ""

    init(listener: PairedListener, onDone: @escaping (Result) -> Void) {
        self.listener = listener
        self.onDone = onDone

        let key = "pairing.json.draft.\(listener.host):\(listener.port)"
        self.draftKey = key
        _jsonText = AppStorage(wrappedValue: "", key)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pairing JSON")
                    .font(.headline)
                    .padding(.top, 8)

                Text("Paste the pairing JSON (nvpair), or scan the daemon QR code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    errorText = nil
                    showQRScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.borderedProminent)

                TextEditor(text: $jsonText)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($editorFocused)
                    .frame(minHeight: 280)
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .navigationTitle("Pair \(listener.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDone(.cancelled)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveManual() }
                        .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
            .alert("Server address mismatch", isPresented: $showMismatchAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Listener is \(mismatchExpected) but pairing blob/QR is \(mismatchGot).\n\nFix the listener or generate a new QR from the correct daemon.")
            }
            .alert(pendingConfirmTitle, isPresented: $showPairConfirmAlert) {
                Button("Cancel", role: .cancel) {
                    pendingLink = nil
                }
                Button("Pair") {
                    guard let link = pendingLink else { return }
                    pendingLink = nil
                    Task { await performQRPair(link) }
                }
            } message: {
                Text(pendingConfirmMessage)
            }
            .sheet(isPresented: $showQRScanner) {
                if #available(iOS 16.0, *),
                   DataScannerViewController.isSupported,
                   DataScannerViewController.isAvailable {
                    QRScannerView { payload in
                        showQRScanner = false
                        Task { await handleQRScanned(payload) }
                    } onCancel: {
                        showQRScanner = false
                    }
                } else {
                    AVFoundationQRScannerView { payload in
                        showQRScanner = false
                        Task { await handleQRScanned(payload) }
                    } onCancel: {
                        showQRScanner = false
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .onAppear {
            errorText = nil
            showMismatchAlert = false
            mismatchExpected = ""
            mismatchGot = ""
        }
    }

    // Step 1: decode + validate + confirm (no network yet)
    @MainActor
    private func handleQRScanned(_ payload: String) async {
        errorText = nil

        do {
            let link = try decodeNovaKeyPairQRLink(payload)

            // HARD CHECK: QR must match the listener you're pairing.
            let expected = "\(listener.host):\(listener.port)"
            let scanned = "\(link.host):\(link.port)"
            guard expected == scanned else {
                mismatchExpected = expected
                mismatchGot = scanned
                showMismatchAlert = true
                onDone(.mismatch(expected: expected, got: scanned))
                return
            }

            pendingLink = link

            pendingConfirmTitle = "Confirm Pairing"
            pendingConfirmMessage =
            """
            Pair NovaKey with:

            \(scanned)

            Only continue if this matches the computer showing the QR code.
            """
            showPairConfirmAlert = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    // Step 2: network + save
    @MainActor
    private func performQRPair(_ link: PairBootstrapLink) async {
        errorText = nil

        do {
            // At this point, link host/port already matches listener host/port.
            let bootstrap = try await fetchPairBootstrap(link)
            let json = try makePairingJSON(from: bootstrap)

            jsonText = json

            let record = try PairingManager.parsePairingJSON(json)
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
            try await postPairComplete(link)

            jsonText = ""
            dismiss()
            onDone(.saved)
        } catch {
            errorText = error.localizedDescription
            onDone(.failed)
        }
    }

    private func saveManual() {
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

            jsonText = ""
            dismiss()
            onDone(.saved)
        } catch {
            errorText = error.localizedDescription
            onDone(.failed)
        }
    }
}

