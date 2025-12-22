//
//  SettingsView.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("clipboardTimeout") private var clipboardTimeoutRaw: String = ClipboardTimeout.s60.rawValue
    @AppStorage("requireFreshBiometric") private var requireFreshBiometric: Bool = true

    private var hasClipboardContent: Bool {
        UIPasteboard.general.hasStrings || !UIPasteboard.general.items.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                }

                Section {
                    Picker("Auto-clear", selection: $clipboardTimeoutRaw) {
                        ForEach(ClipboardTimeout.allCases) { t in
                            Text(t.label).tag(t.rawValue)
                        }
                    }

                    Button("Clear Clipboard Now", role: .destructive) {
                        ClipboardManager.clearNow()
                    }
                    .disabled(!hasClipboardContent)
                } header: {
                    Text("Clipboard")
                } footer: {
                    let timeout = ClipboardTimeout(rawValue: clipboardTimeoutRaw) ?? .s60
                    Text(timeout == .never
                         ? "Clipboard will not be auto-cleared. Consider clearing it manually."
                         : "Clipboard will auto-clear after the selected time and may also clear when the app backgrounds.")
                }

                Section("Security") {
                    Toggle("Require Face ID every time", isOn: $requireFreshBiometric)
                }

                Section("Support") {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
