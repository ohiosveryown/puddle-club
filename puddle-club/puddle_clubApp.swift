//
//  puddle_clubApp.swift
//  puddle-club
//
//  Created by Matthew Pence on 3/3/26.
//

import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct puddle_clubApp: App {
    let container: ModelContainer

    init() {
        // BGTask registration must happen before the first scene is created
        do {
            container = try ModelContainer(for: Screenshot.self, ScreenshotEntity.self, ScreenshotTag.self, PatternStore.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        BackgroundTaskManager.registerTasks(container: container)
    }
 
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
    }
}
