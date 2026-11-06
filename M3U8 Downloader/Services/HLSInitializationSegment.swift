import Foundation

nonisolated struct HLSInitializationSegment: Sendable, Equatable {
    var url: URL
    var encryption: HLSEncryption?
    var byteRange: HLSByteRange?
}
