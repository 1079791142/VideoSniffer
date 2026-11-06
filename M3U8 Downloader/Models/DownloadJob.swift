import Foundation
import SwiftData

@Model
final class DownloadJob {
    var id: UUID
    var title: String
    var sourceURLString: String
    var outputFileName: String
    var statusRawValue: String
    var destinationPath: String?
    var destinationBookmark: Data?
    var tempDirectoryName: String
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var totalBytes: Int64
    var downloadedBytes: Int64
    var segmentCount: Int
    var completedSegmentCount: Int
    var selectedVariantResolution: String?
    var selectedVariantBandwidth: Int?
    var errorMessage: String?
    var finalFilePath: String?

    @Relationship(deleteRule: .cascade, inverse: \DownloadSegment.job)
    var segments: [DownloadSegment]

    init(
        title: String,
        sourceURLString: String,
        outputFileName: String,
        destinationPath: String? = nil,
        destinationBookmark: Data? = nil
    ) {
        let now = Date()
        let identifier = UUID()
        self.id = identifier
        self.title = title
        self.sourceURLString = sourceURLString
        self.outputFileName = outputFileName
        self.statusRawValue = DownloadStatus.queued.rawValue
        self.destinationPath = destinationPath
        self.destinationBookmark = destinationBookmark
        self.tempDirectoryName = identifier.uuidString
        self.createdAt = now
        self.updatedAt = now
        self.startedAt = nil
        self.completedAt = nil
        self.totalBytes = 0
        self.downloadedBytes = 0
        self.segmentCount = 0
        self.completedSegmentCount = 0
        self.selectedVariantResolution = nil
        self.selectedVariantBandwidth = nil
        self.errorMessage = nil
        self.finalFilePath = nil
        self.segments = []
    }

    var status: DownloadStatus {
        get { DownloadStatus(rawValue: statusRawValue) ?? .queued }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var progress: Double {
        guard segmentCount > 0 else { return 0 }
        return min(1, Double(completedSegmentCount) / Double(segmentCount))
    }

    var sourceURL: URL? {
        URL(string: sourceURLString)
    }

    var requiresFMP4PlaylistRefresh: Bool {
        guard !segments.contains(where: \DownloadSegment.isInitializationSegment) else {
            return false
        }
        return segments.contains { segment in
            guard let sourceExtension = URL(string: segment.urlString)?.pathExtension.lowercased() else {
                return false
            }
            return ["m4s", "mp4"].contains(sourceExtension)
                && URL(filePath: segment.localFileName).pathExtension.lowercased() == "ts"
        }
    }

    func markFailed(_ message: String) {
        errorMessage = message
        status = .failed
    }
}
