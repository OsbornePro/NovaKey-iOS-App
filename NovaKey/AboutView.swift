//
//  AboutView.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/22/25.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "NovaKey"
    }

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(appName)
                                .font(.headline)
                            Text("Version \(versionString)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                Section("Links") {
                    Link("Documentation", destination: URL(string: "https://novakey.app")!)
                    Link("NovaKey-Daemon", destination: URL(string: "https://github.com/OsbornePro/NovaKey-Daemon")!)
                    Link("NovaKey-iOS-App", destination: URL(string: "https://github.com/OsbornePro/NovaKey-iOS-App")!)
                    Link("NovaKeyKEMBridge", destination: URL(string: "https://github.com/OsbornePro/NovaKeyKEMBridge")!)
                    Link("OsbornePro", destination: URL(string: "https://osbornepro.com")!)
                }

                Section("Credits") {
                    LabeledContent("Author", value: "Robert H. Osborne")
                    LabeledContent("Logo", value: "⁨Terézia Uhrínková⁩")

                    Text("© \(Calendar.current.component(.year, from: .now), format: .number.grouping(.never)) NovaKey - OsbornePro. All rights reserved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Security") {
                    Text("NovaKey keeps secrets hidden by default—after saving, they’re stored in the iOS Keychain and only revealed after you authenticate to copy or send. When sending to a computer, NovaKey and the listener mutually verify each other and use quantum-resistant (post-quantum) key exchange with modern authenticated encryption to protect the connection. Messages include freshness checks and replay protection, and the listener enforces per-device rate limiting to reduce abuse. NovaKey can also be configured with process whitelisting, so it will only type into apps you explicitly allow. With Two-Man Mode enabled, sending requires a second confirmation on the computer, so a secret can’t be injected without someone approving it there.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
