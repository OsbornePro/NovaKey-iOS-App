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
                    step(1, "Run NovaKey-Daemon on your computer.")
                    step(2, "Add your computer as a Listener in the iPhone app.")
                    step(3, "Pair using the nvpair JSON blob.")
                    step(4, "Set a Send Target.")
                    step(5, "Add a secret, then Send.")
                }

                Section("Pairing") {
                    Text("Pairing connects your phone to a specific NovaKey listener. You’ll paste the nvpair JSON blob into the Pair screen. Treat that blob like a secret.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link("Pairing guide", destination: URL(string: "https://novakey.app/docs/pairing")!)
                }

                Section("Sending & Two-Man Mode") {
                    bullet("If two-man mode is enabled on the daemon, NovaKey will request approval before sending when needed.")
                    bullet("If injection is blocked (focus policy, disarmed state, etc.), the daemon may fall back to clipboard depending on config.")
                    Link("Two-man mode", destination: URL(string: "https://novakey.app/docs/two-man")!)
                    Link("Daemon config", destination: URL(string: "https://novakey.app/docs/config")!)
                }

                Section("Troubleshooting") {
                    bullet("Not paired: open Listeners → Pair/Re-pair.")
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
