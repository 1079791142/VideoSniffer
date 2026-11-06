import SwiftData
import SwiftUI

enum DownloadRuntimeMode {
    case normal
    case demo

    var usesDemoData: Bool {
        self == .demo
    }
}

struct AppLaunchConfiguration {
    static let demoModeArgument = "--demo-mode"
    static let demoModeEnvironmentKey = "M3U8_DOWNLOADER_DEMO_MODE"

    let runtimeMode: DownloadRuntimeMode

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        if arguments.contains(Self.demoModeArgument) || Self.isDemoModeValue(environment[Self.demoModeEnvironmentKey]) {
            runtimeMode = .demo
        } else {
            runtimeMode = .normal
        }
    }

    private static func isDemoModeValue(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.lowercased() {
        case "1", "true", "yes", "demo":
            return true
        default:
            return false
        }
    }
}

@MainActor
enum DemoDownloadSeeder {
    static func seed(into context: ModelContext) {
        for job in PreviewSamples.demoJobs {
            context.insert(job)
        }
        try? context.save()
    }
}

private struct DownloadRuntimeModeKey: EnvironmentKey {
    static let defaultValue: DownloadRuntimeMode = .normal
}

extension EnvironmentValues {
    var downloadRuntimeMode: DownloadRuntimeMode {
        get { self[DownloadRuntimeModeKey.self] }
        set { self[DownloadRuntimeModeKey.self] = newValue }
    }
}
