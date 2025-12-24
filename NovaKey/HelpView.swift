//
//  HelpView.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/22/25.
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Quick Start") {
                    step(1, "Add your computer as a Listener in the phone app.")
                    step(2, "Set the added listener as your Send Target by touching it.")
                    step(3, "Run the install script for NovaKey-Daemon on your computer. The first start will generate a QR code and open it on your computer.")
                    step(4, "Select the listener added on your phone, swipe it right and select 'Pair'.")
                    step(5, "Select the 'Scan QR Code' button and scan the QR code on your computer.")
                    step(6, "Add a secret, then Send!")
                }

                Section("Pairing") {
                    Text("Pairing connects your phone to a specific NovaKey listener. You’ll paste the nvpair JSON blob into the Pair screen. Treat that blob like a secret.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link("Pairing guide", destination: URL(string: "https://novakey.app/docs/pairing")!)
                }

                Section("Sending & Two-Man Mode") {
                    bullet("Two-man mode is enabled by default on the daemon. This means NovaKey will request approval before sending secrets. Two-man mode is kind of like two people turning the key on a nuclear submarine to launch a nuke.")
                    bullet("If text injection is blocked by something, the daemon by default is set to a 'send-to-clipboard' action which you can change in the 'server_config.yaml' file on your computer.")
                    Link("Two-man mode", destination: URL(string: "https://novakey.app/docs/two-man")!)
                    Link("Daemon config", destination: URL(string: "https://novakey.app/docs/config")!)
                }

                Section("Troubleshooting") {
                    bullet("Not paired: open Listeners → Pair/Re-pair. Once you set the IP for a 'Listener' it cannot be changed. You have to delete and re-add the listener if a mistake was made.")
                    bullet("Not armed: disable arming in daemon config or use arm API if enabled.")
                    bullet("Nothing types: check macOS Accessibility permissions or Wayland limitations on Linux.")
                    Link("Troubleshooting", destination: URL(string: "https://novakey.app/docs/troubleshooting")!)
                }

                Section("Support") {
                    Link("NovaKey Docs", destination: URL(string: "https://novakey.app")!)
                    Link("Security Findings", destination: URL(string: "https://github.com/OsbornePro/NovaKey-Daemon/blob/main/SECURITY.md")!)
                    Link("GitHub Issues", destination: URL(string: "https://github.com/OsbornePro/NovaKey-Daemon/issues")!)
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n).")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Text(text)
                .font(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func bullet(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}
