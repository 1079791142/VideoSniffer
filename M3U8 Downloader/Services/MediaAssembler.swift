import AVFoundation
import Foundation

struct MediaAssembler: Sendable {
    let fileStore = DownloadFileStore()

    func assemble(job: DownloadJob) async throws -> URL {
#if os(iOS)
        let playlistURL = try fileStore.finalMediaURL(for: job)
        if FileManager.default.fileExists(atPath: playlistURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: playlistURL)
        }
        try hlsPlaylist(for: job).write(to: playlistURL, atomically: true, encoding: .utf8)
        return playlistURL
#else
        let intermediateURL = try fileStore.intermediateMediaURL(for: job)
        if FileManager.default.fileExists(atPath: intermediateURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: intermediateURL)
        }
        guard FileManager.default.createFile(atPath: intermediateURL.path(percentEncoded: false), contents: nil) else {
            throw DownloadError.fileAssemblyFailed
        }

        try writeResources(for: job, to: intermediateURL)

        let mp4URL = try fileStore.finalMediaURL(for: job)
        if FileManager.default.fileExists(atPath: mp4URL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: mp4URL)
        }
        try await exportMedia(inputURL: intermediateURL, outputURL: mp4URL, outputFileType: .mp4)
        try fileStore.removeAssemblyWorkingFiles(for: job, preserving: mp4URL)
        return mp4URL
#endif
    }

    func hlsPlaylist(for job: DownloadJob) throws -> String {
        let sortedSegments = job.segments
            .filter { !$0.isInitializationSegment }
            .sorted(by: { $0.index < $1.index })
        let targetDuration = max(1, Int((sortedSegments.compactMap(\.duration).max() ?? 1).rounded(.up)))
        var segmentEntries = ""

        let initializationSegments = job.segments.filter(\DownloadSegment.isInitializationSegment)

        for segment in sortedSegments {
            if let initializationSegment = initializationSegments.first(where: { $0.index == segment.index }) {
                try validate(resource: initializationSegment, job: job)
                segmentEntries += "#EXT-X-MAP:URI=\"Segments/\(initializationSegment.localFileName)\"\n"
            }

            try validate(resource: segment, job: job)

            let duration = max(segment.duration ?? 0.001, 0.001)
            let durationText = duration.formatted(.number.precision(.fractionLength(3)).locale(Locale(identifier: "en_US_POSIX")))
            segmentEntries += """
            #EXTINF:\(durationText),
            Segments/\(segment.localFileName)

            """
        }

        return """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-TARGETDURATION:\(targetDuration)
        #EXT-X-MEDIA-SEQUENCE:0
        \(segmentEntries)\
        #EXT-X-ENDLIST

        """
    }

    private func validate(resource: DownloadSegment, job: DownloadJob) throws {
        let resourceURL = try fileStore.segmentURL(for: resource, job: job)
        let attributes = try FileManager.default.attributesOfItem(atPath: resourceURL.path(percentEncoded: false))
        let byteLength = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard byteLength > 0 else {
            throw DownloadError.fileAssemblyFailed
        }
    }

    func writeResources(for job: DownloadJob, to outputURL: URL) throws {
        guard let handle = try? FileHandle(forWritingTo: outputURL) else {
            throw DownloadError.fileAssemblyFailed
        }
        defer {
            try? handle.close()
        }

        for resource in sortedResources(for: job) {
            let resourceURL = try fileStore.segmentURL(for: resource, job: job)
            try handle.write(contentsOf: Data(contentsOf: resourceURL))
        }
    }

    private func sortedResources(for job: DownloadJob) -> [DownloadSegment] {
        job.segments.sorted {
            if $0.index == $1.index {
                return $0.isInitializationSegment && !$1.isInitializationSegment
            }
            return $0.index < $1.index
        }
    }

#if os(macOS)
    private func exportMedia(inputURL: URL, outputURL: URL, outputFileType: AVFileType) async throws {
        let asset = AVURLAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw DownloadError.mp4ExportFailed(String(localized: .theMediaCannotBeExportedWithPassthroughPreset))
        }
        exportSession.shouldOptimizeForNetworkUse = true

        do {
            try await exportSession.export(to: outputURL, as: outputFileType)
        } catch is CancellationError {
            throw DownloadError.canceled
        } catch {
            throw DownloadError.mp4ExportFailed(error.localizedDescription)
        }
    }
#endif
}
