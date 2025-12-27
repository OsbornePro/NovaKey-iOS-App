//
//  PairingPasteSheet.swift
//  NovaKey
//

import SwiftUI
import VisionKit
import UniformTypeIdentifiers
import Security
import NovaKeyKEM

private final class RefBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

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
    @State private var isWorking = false

    @State private var showMismatchAlert = false
    @State private var mismatchExpected = ""
    @State private var mismatchGot = ""

    @State private var showQRScanner = false
    @State private var pendingLink: PairBootstrapLink?
    @State private var pendingConfirmTitle = "Confirm Pairing"
    @State private var pendingConfirmMessage = ""
    @State private var showPairConfirmDialog = false

    @State private var showImporter = false

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

                Text("Paste nvpair JSON, import a file, or scan the daemon QR code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        guard !isWorking else { return }
                        errorText = nil
                        pendingLink = nil
                        showQRScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        guard !isWorking else { return }
                        errorText = nil
                        if let s = UIPasteboard.general.string, !s.isEmpty {
                            jsonText = s
                        } else {
                            errorText = "Clipboard is empty."
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        guard !isWorking else { return }
                        errorText = nil
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        guard !isWorking else { return }
                        errorText = nil
                        jsonText = ""
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                TextEditor(text: $jsonText)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($editorFocused)
                    .frame(minHeight: 280)
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if isWorking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Working…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }

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
                    .disabled(isWorking)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAction() }
                        .disabled(isWorking || jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .confirmationDialog(
                pendingConfirmTitle,
                isPresented: $showPairConfirmDialog,
                titleVisibility: .visible
            ) {
                Button("Pair") {
                    guard let link = pendingLink else { return }
                    Task { await performKyberPair(link) }
                }
                Button("Cancel", role: .cancel) { pendingLink = nil }
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
                    } onCancel: { showQRScanner = false }
                } else {
                    AVFoundationQRScannerView { payload in
                        showQRScanner = false
                        Task { await handleQRScanned(payload) }
                    } onCancel: { showQRScanner = false }
                    .ignoresSafeArea()
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let data = try Data(contentsOf: url)
                    guard let s = String(data: data, encoding: .utf8) else {
                        errorText = "File is not UTF-8 text."
                        return
                    }
                    jsonText = s
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
        .onAppear {
            errorText = nil
            showMismatchAlert = false
            pendingLink = nil
        }
    }

    @MainActor
    private func saveAction() {
        errorText = nil
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().hasPrefix("novakey://") {
            do {
                let link = try decodeNovaKeyPairQRLink(trimmed)
                presentConfirm(for: link)
            } catch {
                errorText = error.localizedDescription
                onDone(.failed)
            }
            return
        }

        saveManualJSON()
    }

    @MainActor
    private func handleQRScanned(_ payload: String) async {
        errorText = nil
        do {
            let link = try decodeNovaKeyPairQRLink(payload)

            let expected = "\(listener.host):\(listener.port)"
            let scanned = "\(link.host):\(link.port)"
            guard expected == scanned else {
                mismatchExpected = expected
                mismatchGot = scanned
                showMismatchAlert = true
                onDone(.mismatch(expected: expected, got: scanned))
                return
            }

            presentConfirm(for: link)
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func presentConfirm(for link: PairBootstrapLink) {
        pendingLink = link
        pendingConfirmTitle = "Confirm Pairing"
        pendingConfirmMessage =
        """
        Pair NovaKey with:

        \(link.host):\(link.port)

        Only continue if this matches the computer showing the QR code.
        """
        showPairConfirmDialog = true
    }

    private func performKyberPair(_ link: PairBootstrapLink) async {
        await MainActor.run {
            errorText = nil
            isWorking = true
        }
        defer { Task { @MainActor in isWorking = false } }

        do {
            let client = NovaKeyPairClient()
            let serverKeyBox = RefBox<PairServerKey?>(nil)

            let deviceID = "ios-\(UUID().uuidString.prefix(8))"
            let deviceKeyHex = randomHex(bytes: 32)

            let registerCTBox = RefBox<Data?>(nil)
            let aeadKeyBox = RefBox<Data?>(nil)

            try await client.pair(
                host: link.host,
                port: link.port,
                token: link.token,
                buildRegisterFrame: { serverKey, tokenRawURLB64 in
                    serverKeyBox.value = serverKey

                    var err: NSError?
                    let bundleObj = NovakeykemBuildPairRegisterBundle(
                        serverKey.goJSON(),
                        tokenRawURLB64,
                        deviceID,
                        deviceKeyHex,
                        &err
                    )
                    if let err { throw err }

                    guard let bundleData = bundleObj else {
                        throw NovaKeyPairError.protocolError("BuildPairRegisterBundle returned nil")
                    }

                    let parts = try unpackRegisterBundle(bundleData)

                    registerCTBox.value = parts.ct
                    aeadKeyBox.value = parts.key
                    return parts.frame
                },
                handleAck: { serverKey, ack, _ in
                    serverKeyBox.value = serverKey

                    guard let regCT = registerCTBox.value,
                          let aeadKey = aeadKeyBox.value else {
                        throw NovaKeyPairError.protocolError("missing register state")
                    }

                    var err: NSError?
                    let reg = regCT          // Data (non-optional)
                    let key = aeadKey        // Data (non-optional)
                    _ = NovakeykemDecryptPairAck(ack, reg, key, &err)
                    if let err { throw err }
                }
            )

            guard let sk = serverKeyBox.value else {
                throw NovaKeyPairError.protocolError("missing server_key")
            }
            guard let keyData = Data(hexString: deviceKeyHex), keyData.count == 32 else {
                throw PairingErrors.invalidDeviceKeyLength
            }

            let rec = PairingRecord(
                deviceID: deviceID,
                deviceKey: keyData,
                serverHost: listener.host,
                serverPort: listener.port,
                serverPubB64: sk.kyber_pub_b64
            )

            try PairingManager.save(rec)

            await MainActor.run {
                jsonText = ""
                dismiss()
                onDone(.saved)
            }

        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
                onDone(.failed)
            }
        }
    }

    private func saveManualJSON() {
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

private func randomHex(bytes: Int) -> String {
    var b = [UInt8](repeating: 0, count: bytes)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
    return b.map { String(format: "%02x", $0) }.joined()
}

// Bundle format: [u32 frameLen][frame][u16 ctLen][ct][32 key]
private func unpackRegisterBundle(_ bundle: Data) throws -> (frame: Data, ct: Data, key: Data) {
    var idx = 0

    func readU32() throws -> Int {
        guard bundle.count >= idx + 4 else { throw NovaKeyPairError.protocolError("bundle short (u32)") }
        let v = bundle[idx..<idx+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        idx += 4
        return Int(v)
    }

    func readU16() throws -> Int {
        guard bundle.count >= idx + 2 else { throw NovaKeyPairError.protocolError("bundle short (u16)") }
        let v = bundle[idx..<idx+2].reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        idx += 2
        return Int(v)
    }

    let frameLen = try readU32()
    guard bundle.count >= idx + frameLen else { throw NovaKeyPairError.protocolError("bundle short (frame)") }
    let frame = bundle[idx..<idx+frameLen]
    idx += frameLen

    let ctLen = try readU16()
    guard bundle.count >= idx + ctLen + 32 else { throw NovaKeyPairError.protocolError("bundle short (ct/key)") }
    let ct = bundle[idx..<idx+ctLen]
    idx += ctLen

    let key = bundle[idx..<idx+32]
    idx += 32

    return (Data(frame), Data(ct), Data(key))
}

private extension PairServerKey {
    func goJSON() -> String {
        let obj: [String: Any] = [
            "op": op,
            "v": v,
            "kid": kid,
            "kyber_pub_b64": kyber_pub_b64,
            "fp16_hex": fp16_hex as Any,
            "expires_unix": expires_unix
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
