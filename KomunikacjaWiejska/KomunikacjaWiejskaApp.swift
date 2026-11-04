//
//  KomunikacjaWiejskaApp.swift
//  KomunikacjaWiejska
//
//  Created by Lemon on 2026-11-05.
//

import SwiftUI
import SwiftData

@main
struct KomunikacjaWiejskaApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
