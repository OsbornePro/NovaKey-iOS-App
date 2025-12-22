//
//  Appearance-Mode.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/21/25.
//

import SwiftUI

/// Shared theme setting used by NovaKeyApp / SettingsView / anywhere else.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}
