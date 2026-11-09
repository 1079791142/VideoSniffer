import Foundation

/// One media candidate reported by the sniffing script.
///
/// Everything in here originates from web content and must be treated as
/// untrusted data: it is only ever used as a URL to offer to the user.
nonisolated struct SniffedMedia: Sendable, Hashable, Identifiable {
    /// The absolute `http(s)` URL of the media resource.
    let urlString: String
    let kind: SniffedMediaKind
    /// The page that reported this candidate, when the script could provide it.
    let pageURLString: String?
    let discoveredAt: Date

    var id: String { urlString }

    var url: URL? { URL(string: urlString) }
}
