//
//  Models.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/20/25.
//
import Foundation
import SwiftData

@Model
final class SecretItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
final class PairedListener {
    var id: UUID
    var displayName: String
    var host: String
    var port: Int
    var isDefault: Bool

    // NEW
    var notes: String

    init(displayName: String, host: String, port: Int, isDefault: Bool, notes: String = "") {
        self.id = UUID()
        self.displayName = displayName
        self.host = host
        self.port = port
        self.isDefault = isDefault
        self.notes = notes
    }
}

@Model
final class LocalAccount {
    @Attribute(.unique) var id: UUID
    var provider: String
    var displayName: String
    var email: String
    var signedInAt: Date

    init(provider: String, displayName: String, email: String) {
        self.id = UUID()
        self.provider = provider
        self.displayName = displayName
        self.email = email
        self.signedInAt = .now
    }
}
