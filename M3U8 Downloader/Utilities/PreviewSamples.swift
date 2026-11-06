import Foundation
import SwiftData

@MainActor
enum PreviewSamples {
    static let settings = SettingsStore(defaults: .standard, keychain: .shared)

    static func modelContainer() -> ModelContainer {
        do {
            let schema = Schema([DownloadJob.self, DownloadSegment.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create preview ModelContainer: \(error)")
        }
    }

    static var downloadingJob: DownloadJob {
        let job = DownloadJob(
            title: "Sample Stream",
            sourceURLString: "https://example.com/video/master.m3u8",
            outputFileName: "Sample Stream"
        )
        job.status = .downloading
        job.segmentCount = 5
        job.completedSegmentCount = 3
        job.downloadedBytes = 18_420_736
        job.selectedVariantResolution = "1920x1080"
        job.selectedVariantBandwidth = 4_000_000
        job.startedAt = Date.now.addingTimeInterval(-120)
        job.segments = [
            segment(index: 0, status: .completed, byteCount: 6_291_456),
            segment(index: 1, status: .completed, byteCount: 6_144_000),
            segment(index: 2, status: .completed, byteCount: 5_985_280),
            segment(index: 3, status: .downloading, byteCount: 0),
            segment(index: 4, status: .pending, byteCount: 0)
        ]
        return job
    }

    static var pausedJob: DownloadJob {
        let job = downloadingJob
        job.title = "Paused Episode"
        job.outputFileName = "Paused Episode"
        job.status = .paused
        return job
    }

    static var completedJob: DownloadJob {
        let job = downloadingJob
        job.title = "Completed Movie"
        job.outputFileName = "Completed Movie"
        job.status = .completed
        job.segmentCount = 5
        job.completedSegmentCount = 5
        job.downloadedBytes = 31_457_280
        job.finalFilePath = URL.documentsDirectory.appending(path: "Completed Movie.mp4").path(percentEncoded: false)
        job.completedAt = Date.now
        for segment in job.segments {
            segment.status = .completed
            if segment.byteCount == 0 {
                segment.byteCount = 6_291_456
            }
        }
        return job
    }

    static var failedJob: DownloadJob {
        let job = downloadingJob
        job.title = "Failed Stream"
        job.outputFileName = "Failed Stream"
        job.status = .failed
        job.errorMessage = "HTTP 403 while downloading a media segment."
        if let segment = job.segments.last {
            segment.status = .failed
            segment.errorMessage = job.errorMessage
        }
        return job
    }
    
    static var demoJobs: [DownloadJob] {
        let now = Date.now

        let nature = completedJob
        nature.title = "Iceland Nature Documentary"
        nature.sourceURLString = "https://media.example.com/iceland/master.m3u8"
        nature.outputFileName = "Iceland Nature Documentary"
        nature.segmentCount = 18
        nature.completedSegmentCount = 18
        nature.downloadedBytes = 1_284_358_144
        nature.selectedVariantResolution = "3840x2160"
        nature.selectedVariantBandwidth = 12_000_000
        nature.finalFilePath = URL.documentsDirectory.appending(path: "Iceland Nature Documentary.mp4").path(percentEncoded: false)
        nature.createdAt = now.addingTimeInterval(-86_400)
        nature.startedAt = now.addingTimeInterval(-84_600)
        nature.completedAt = now.addingTimeInterval(-82_140)

        let conference = downloadingJob
        conference.title = "WWDC Session Capture"
        conference.sourceURLString = "https://media.example.com/wwdc/session-101/master.m3u8"
        conference.outputFileName = "WWDC Session Capture"
        conference.segmentCount = 24
        conference.completedSegmentCount = 16
        conference.downloadedBytes = 734_003_200
        conference.selectedVariantResolution = "1920x1080"
        conference.selectedVariantBandwidth = 6_500_000
        conference.createdAt = now.addingTimeInterval(-5_400)
        conference.startedAt = now.addingTimeInterval(-5_280)

        let course = pausedJob
        course.title = "Advanced SwiftUI Course"
        course.sourceURLString = "https://courses.example.com/swiftui/playlist.m3u8"
        course.outputFileName = "Advanced SwiftUI Course"
        course.segmentCount = 14
        course.completedSegmentCount = 6
        course.downloadedBytes = 402_653_184
        course.selectedVariantResolution = "1280x720"
        course.selectedVariantBandwidth = 3_200_000
        course.createdAt = now.addingTimeInterval(-18_000)
        course.startedAt = now.addingTimeInterval(-17_820)

        let live = job(status: .queued)
        live.title = "Evening News Live Replay"
        live.sourceURLString = "https://live.example.com/news/replay.m3u8"
        live.outputFileName = "Evening News Live Replay"
        live.selectedVariantResolution = "1920x1080"
        live.selectedVariantBandwidth = 5_200_000
        live.createdAt = now.addingTimeInterval(-900)

        let encrypted = failedJob
        encrypted.title = "Encrypted Event Archive"
        encrypted.sourceURLString = "https://events.example.com/archive/master.m3u8"
        encrypted.outputFileName = "Encrypted Event Archive"
        encrypted.segmentCount = 32
        encrypted.completedSegmentCount = 11
        encrypted.downloadedBytes = 587_202_560
        encrypted.selectedVariantResolution = "1920x1080"
        encrypted.selectedVariantBandwidth = 4_800_000
        encrypted.errorMessage = "AES-128 key request returned HTTP 403."
        encrypted.createdAt = now.addingTimeInterval(-172_800)
        encrypted.startedAt = now.addingTimeInterval(-172_680)

        return [live, conference, course, nature, encrypted]
    }

    static func job(status: DownloadStatus) -> DownloadJob {
        let job = downloadingJob
        job.title = "\(String(localized: status.title)) Stream"
        job.outputFileName = job.title
        job.status = status

        switch status {
        case .queued:
            job.segmentCount = 0
            job.completedSegmentCount = 0
            job.downloadedBytes = 0
            job.segments = []
        case .preparing:
            job.segmentCount = 0
            job.completedSegmentCount = 0
            job.downloadedBytes = 0
            job.segments = []
        case .downloading:
            break
        case .paused:
            job.completedSegmentCount = 2
            job.downloadedBytes = 12_435_456
            for segment in job.segments where segment.status == .downloading {
                segment.status = .pending
            }
        case .assembling:
            job.completedSegmentCount = job.segmentCount
            job.downloadedBytes = 31_457_280
            for segment in job.segments {
                segment.status = .completed
                if segment.byteCount == 0 {
                    segment.byteCount = 6_291_456
                }
            }
        case .completed:
            job.completedSegmentCount = job.segmentCount
            job.downloadedBytes = 31_457_280
            job.finalFilePath = URL.documentsDirectory.appending(path: "\(job.outputFileName).mp4").path(percentEncoded: false)
            for segment in job.segments {
                segment.status = .completed
                if segment.byteCount == 0 {
                    segment.byteCount = 6_291_456
                }
            }
        case .failed:
            job.errorMessage = "HTTP 403 while downloading a media segment."
            if let segment = job.segments.last {
                segment.status = .failed
                segment.errorMessage = job.errorMessage
            }
        case .canceled:
            job.completedSegmentCount = 1
            job.downloadedBytes = 6_291_456
            for segment in job.segments where segment.status == .downloading {
                segment.status = .pending
            }
        }

        return job
    }

    static func segment(index: Int = 0, status: SegmentStatus = .completed, byteCount: Int64 = 6_291_456) -> DownloadSegment {
        let segment = DownloadSegment(
            index: index,
            urlString: "https://example.com/video/segment-\(index).ts",
            localFileName: "segment-\(index).ts"
        )
        segment.status = status
        segment.byteCount = byteCount
        return segment
    }
}
