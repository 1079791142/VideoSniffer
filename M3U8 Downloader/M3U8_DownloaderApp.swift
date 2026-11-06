//
//  M3U8_DownloaderApp.swift
//  M3U8 Downloader
//
//  Created by 林思行 on 2026/5/14.
//

import SwiftUI
import SwiftData

@main
struct M3U8_DownloaderApp: App {
    @State private var settings = SettingsStore()
    private let launchConfiguration: AppLaunchConfiguration
    private let sharedModelContainer: ModelContainer

    init() {
        let launchConfiguration = AppLaunchConfiguration()
        let sharedModelContainer = Self.makeModelContainer(isStoredInMemoryOnly: launchConfiguration.runtimeMode.usesDemoData)
        if launchConfiguration.runtimeMode.usesDemoData {
            DemoDownloadSeeder.seed(into: sharedModelContainer.mainContext)
        }
        self.launchConfiguration = launchConfiguration
        self.sharedModelContainer = sharedModelContainer
    }

    private static func makeModelContainer(isStoredInMemoryOnly: Bool) -> ModelContainer {
        let schema = Schema([
            DownloadJob.self,
            DownloadSegment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
#if os(macOS)
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 600)
        .modelContainer(sharedModelContainer)
        .environment(settings)
        .environment(\.downloadRuntimeMode, launchConfiguration.runtimeMode)

        Settings {
            SettingsSceneView(settings: settings)
        }
        .modelContainer(sharedModelContainer)
        .environment(\.downloadRuntimeMode, launchConfiguration.runtimeMode)
#else
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .environment(settings)
        .environment(\.downloadRuntimeMode, launchConfiguration.runtimeMode)
#endif
    }
}

#if os(macOS)
private struct SettingsSceneView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.downloadRuntimeMode) private var runtimeMode
    let settings: SettingsStore
    @State private var engine: DownloadEngine?

    var body: some View {
        SettingsView(engine: engine)
            .environment(settings)
            .task {
                if engine == nil {
                    engine = DownloadEngine(modelContext: modelContext, settings: settings, mode: runtimeMode)
                }
            }
    }
}
#endif
