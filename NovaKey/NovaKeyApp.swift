//
//  NovaKeyApp.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/17/25.
//

import SwiftUI

@main
struct NovaKeyApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
