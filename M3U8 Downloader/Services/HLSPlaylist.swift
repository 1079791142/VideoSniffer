import Foundation

nonisolated struct HLSPlaylist: Sendable {
    var sourceURL: URL
    var variant: HLSVariant?
    var segments: [HLSSegment]
}

nonisolated struct HLSVariant: Sendable {
    var url: URL
    var bandwidth: Int
    var resolution: String?
}

nonisolated struct HLSSegment: Sendable {
    var index: Int
    var url: URL
    var duration: Double?
    var encryption: HLSEncryption?
    var byteRange: HLSByteRange?
    var initializationSegment: HLSInitializationSegment?
}

nonisolated struct HLSEncryption: Sendable, Equatable {
    var method: String
    var keyURL: URL
    var initializationVector: Data?
}

nonisolated struct HLSByteRange: Sendable, Equatable {
    var length: Int64
    var offset: Int64
}

nonisolated enum HLSPlaylistError: LocalizedError {
    case invalidPlaylist
    case noSegments
    case unsupportedEncryption(String)
    case missingKeyURI
    case invalidByteRange(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlaylist:
            String(localized: .thePlaylistIsNotAValidM3U8Document)
        case .noSegments:
            String(localized: .thePlaylistDoesNotContainDownloadableMediaSegments)
        case .unsupportedEncryption(let method):
            String(localized: .unsupportedHlsEncryptionMethod(method))
        case .missingKeyURI:
            String(localized: .theEncryptedPlaylistIsMissingItsKeyUri)
        case .invalidByteRange(let value):
            String(localized: .invalidHlsByteRange(value))
        }
    }
}
