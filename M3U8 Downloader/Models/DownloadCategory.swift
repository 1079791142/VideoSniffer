import SwiftUI

enum DownloadCategory: String, CaseIterable, Identifiable {
    case all
    case active
    case terminal

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: .all
        case .active: .active
        case .terminal: .completed
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .active: "arrow.down.circle"
        case .terminal: "checkmark.circle"
        }
    }

    func contains(_ job: DownloadJob) -> Bool {
        switch self {
        case .all:
            true
        case .active:
            !job.status.isTerminal
        case .terminal:
            job.status.isTerminal
        }
    }
}
