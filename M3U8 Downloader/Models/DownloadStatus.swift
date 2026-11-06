import SwiftUI

enum DownloadStatus: String, Codable, CaseIterable, Identifiable {
    case queued
    case preparing
    case downloading
    case paused
    case assembling
    case completed
    case failed
    case canceled

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .queued: .queued
        case .preparing: .preparing
        case .downloading: .downloading
        case .paused: .paused
        case .assembling: .assembling
        case .completed: .completed
        case .failed: .failed
        case .canceled: .canceled
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .canceled:
            true
        case .queued, .preparing, .downloading, .paused, .assembling:
            false
        }
    }
    
    var statusColor: Color {
        switch self {
        case .queued: .gray
        case .completed: .green
        case .failed, .canceled: .red
        case .paused: .orange
        case .assembling: .purple
        case .preparing, .downloading: .blue
        }
    }
}

enum SegmentStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed

    var title: LocalizedStringResource {
        switch self {
        case .pending: .pending
        case .downloading: .downloading
        case .completed: .completed
        case .failed: .failed
        }
    }
}
