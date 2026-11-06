import SwiftUI
import SwiftData

@Model
final class DownloadSegment {
    var index: Int
    var urlString: String
    var localFileName: String
    var kindRawValue: String = DownloadSegmentKind.media.rawValue
    var statusRawValue: String
    var byteCount: Int64
    var retryCount: Int
    var duration: Double?
    var errorMessage: String?
    var encryptionMethod: String?
    var keyURLString: String?
    var initializationVectorHex: String?
    var byteRangeLength: Int64?
    var byteRangeOffset: Int64?
    var job: DownloadJob?

    init(
        index: Int,
        urlString: String,
        localFileName: String,
        kind: DownloadSegmentKind = .media,
        duration: Double? = nil,
        encryptionMethod: String? = nil,
        keyURLString: String? = nil,
        initializationVectorHex: String? = nil,
        byteRangeLength: Int64? = nil,
        byteRangeOffset: Int64? = nil
    ) {
        self.index = index
        self.urlString = urlString
        self.localFileName = localFileName
        self.kindRawValue = kind.rawValue
        self.statusRawValue = SegmentStatus.pending.rawValue
        self.byteCount = 0
        self.retryCount = 0
        self.duration = duration
        self.errorMessage = nil
        self.encryptionMethod = encryptionMethod
        self.keyURLString = keyURLString
        self.initializationVectorHex = initializationVectorHex
        self.byteRangeLength = byteRangeLength
        self.byteRangeOffset = byteRangeOffset
    }

    var status: SegmentStatus {
        get { SegmentStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    var kind: DownloadSegmentKind {
        DownloadSegmentKind(rawValue: kindRawValue) ?? .media
    }

    var isInitializationSegment: Bool {
        kind == .initialization
    }
    
    var statusColor: Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .downloading: .blue
        case .pending: .secondary
        }
    }
}
