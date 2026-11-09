import Foundation

/// The kind of media a sniffed URL points at.
///
/// The value is produced by the injected JavaScript (`hls` / `file`) and is
/// never trusted blindly: the kind is re-derived from the URL when the value is
/// missing or unknown.
nonisolated enum SniffedMediaKind: String, Sendable, CaseIterable {
    case hls
    case file

    init(reportedValue: String?, url: URL) {
        if let reportedValue, let kind = SniffedMediaKind(rawValue: reportedValue) {
            self = kind
        } else {
            self = .inferred(from: url)
        }
    }

    /// Mirrors `kindFor` in `SniffingScript`: an `.m3u8` on the path means an
    /// HLS playlist, anything else that was reported is treated as a file.
    static func inferred(from url: URL) -> SniffedMediaKind {
        if url.path(percentEncoded: false).lowercased().contains("m3u8") {
            return .hls
        }
        return .file
    }

    var title: LocalizedStringResource {
        switch self {
        case .hls: .hlsPlaylist
        case .file: .videoFile
        }
    }

    var systemImage: String {
        switch self {
        case .hls: "dot.radiowaves.left.and.right"
        case .file: "film"
        }
    }
}
