//
//  VaultTransferEntryViews.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import SwiftUI

/// Compatibility shim so ContentView can keep calling ExportVaultView / ImportVaultView.
/// Both routes show the same Import/Export screen.
struct ExportVaultView: View {
    var body: some View {
        VaultTransferViews()
    }
}

struct ImportVaultView: View {
    var body: some View {
        VaultTransferViews()
    }
}
