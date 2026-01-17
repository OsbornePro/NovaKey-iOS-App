//
//  VaultFileDocument.swift
//  NovaKey
//
//  Created by Robert Osborne on 1/17/26.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Custom file type for NovaKey vault exports (recommended).
    /// If don't want a custom extension, you can remove this and use .json only.
    static var novaKeyVault: UTType {
        // Exported type identifier should be unique and stable
        UTType(exportedAs: "com.novakey.vault")
    }
}

/// Minimal-but-solid FileDocument so we can use fileExporter with raw Data.
/// - Reads/writes raw bytes exactly.
/// - Supports JSON and an optional custom vault type.
/// - Uses atomic writes.
struct VaultFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        // Accept both, so users can import older .json exports too.
        [.novaKeyVault, .json]
    }

    /// If you want the exporter to save as .novakeyvault by default,
    /// pass `.novaKeyVault` as the exporter content type.
    static var writableContentTypes: [UTType] {
        [.novaKeyVault, .json]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        // Only accept regular file contents; do not silently treat missing contents as empty.
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Atomic write: the system writes to a temp file and swaps it in.
        // Prevents partial/corrupted files if something interrupts save.
        FileWrapper(regularFileWithContents: data)
    }
}
