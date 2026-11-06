import Foundation
import SwiftData
import Testing
@testable import M3U8_Downloader

#if os(iOS) && RUN_MUX_HLS_INTEGRATION_TESTS
import AVFoundation
import Combine
#endif

struct M3U8DownloaderTests {
#if os(iOS) && RUN_MUX_HLS_INTEGRATION_TESTS
    @Test @MainActor func muxTransportStreamDownloadsAsPlayableFinalMediaOnIOS() async throws {
        let playlistURL = try #require(URL(string: "https://test-streams.mux.dev/x36xhzz/url_2/193039199_mp4_h264_aac_ld_7.m3u8"))
        let (playlistData, playlistResponse) = try await URLSession.shared.data(from: playlistURL)
        let httpResponse = try #require(playlistResponse as? HTTPURLResponse)
        #expect((200..<300).contains(httpResponse.statusCode))
        let playlistText = String(decoding: playlistData, as: UTF8.self)
        let playlist = try HLSPlaylistParser().parse(text: playlistText, sourceURL: playlistURL)

        let job = DownloadJob(
            title: "Mux Transport Stream",
            sourceURLString: playlistURL.absoluteString,
            outputFileName: "Mux Transport Stream"
        )
        let fileStore = DownloadFileStore()
        defer {
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        let jobDirectory = try fileStore.segmentsDirectory(for: job)
        for segment in playlist.segments.prefix(6) {
            let downloadSegment = DownloadSegment(
                index: segment.index,
                urlString: segment.url.absoluteString,
                localFileName: "segment-\(segment.index).ts",
                duration: segment.duration,
                byteRangeLength: segment.byteRange?.length,
                byteRangeOffset: segment.byteRange?.offset
            )
            job.segments.append(downloadSegment)

            let request = SegmentRequest(
                id: downloadSegment.persistentModelID,
                index: downloadSegment.index,
                urlString: downloadSegment.urlString,
                outputURL: jobDirectory.appending(path: downloadSegment.localFileName),
                retryLimit: 1,
                encryptionMethod: nil,
                keyURLString: nil,
                initializationVectorHex: nil,
                byteRangeLength: downloadSegment.byteRangeLength,
                byteRangeOffset: downloadSegment.byteRangeOffset
            )
            _ = try await SegmentDownloader(configuration: .ephemeral).download(request)
        }

        let outputURL = try await MediaAssembler().assemble(job: job)
        let localPlaylistData = try Data(contentsOf: outputURL)
        let localPlaylistText = String(decoding: localPlaylistData, as: UTF8.self)
        #expect(localPlaylistText.localizedStandardContains("Segments/segment-0.ts"))

        let firstSegmentURL = outputURL.deletingLastPathComponent()
            .appending(path: "Segments", directoryHint: .isDirectory)
            .appending(path: "segment-0.ts")
        let firstSegmentData = try Data(contentsOf: firstSegmentURL)
        #expect(firstSegmentData.first == 0x47)

        let server = try LocalHLSServer(
            rootDirectory: outputURL.deletingLastPathComponent(),
            playlistFileName: outputURL.lastPathComponent
        )
        try await server.start()
        defer {
            server.stop()
        }

        let playbackURL = try server.playlistURL()
        let player = AVPlayer(url: playbackURL)
        player.play()
        defer {
            player.pause()
        }
        let status = try await playerItemStatus(for: try #require(player.currentItem))

        #expect(outputURL.pathExtension == "m3u8")
        #expect(status == .readyToPlay)
    }
#endif

#if os(iOS)
    @Test @MainActor func finalMediaURLUsesLocalHLSPlaylistOnIOS() throws {
        let job = DownloadJob(
            title: "Local HLS",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Local HLS"
        )
        let fileStore = DownloadFileStore()
        defer {
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        #expect(try fileStore.finalMediaURL(for: job).pathExtension == "m3u8")
    }

    @Test @MainActor func finalMediaURLRecoversFromStaleStoredPathOnIOS() throws {
        let job = DownloadJob(
            title: "Restored Local HLS",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Restored Local HLS"
        )
        let fileStore = DownloadFileStore()
        defer {
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        job.finalFilePath = "/stale/container/path/Restored Local HLS.m3u8"
        let recoveredURL = try fileStore.finalMediaURL(for: job)
        try "#EXTM3U\n#EXT-X-ENDLIST\n".write(to: recoveredURL, atomically: true, encoding: .utf8)

        #expect(!FileManager.default.fileExists(atPath: job.finalFilePath ?? ""))
        #expect(FileManager.default.fileExists(atPath: recoveredURL.path(percentEncoded: false)))
    }
#endif

    @Test @MainActor func deletingRecordOnlyRemovesTaskDirectory() throws {
        let job = DownloadJob(
            title: "Stored Media",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Stored Media"
        )
        let fileStore = DownloadFileStore()
        let segment = DownloadSegment(
            index: 0,
            urlString: "https://example.com/video/0.ts",
            localFileName: "segment-0.ts"
        )
        job.segments = [segment]
        try Data([0x47]).write(to: fileStore.segmentURL(for: segment, job: job))
        let finalURL = try fileStore.finalMediaURL(for: job)
        try Data([0x47, 0x40, 0x11]).write(to: finalURL)
        job.finalFilePath = finalURL.path(percentEncoded: false)
        defer {
            try? FileManager.default.removeItem(at: finalURL)
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        try fileStore.removeFiles(for: job, includingDownloadedFile: false)

        #expect(!FileManager.default.fileExists(atPath: fileStore.taskDirectoryURL(for: job).path(percentEncoded: false)))
    }

    @Test @MainActor func storageUsageIncludesTaskDirectoryFiles() throws {
        let job = DownloadJob(
            title: "Stored Segments",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Stored Segments"
        )
        let fileStore = DownloadFileStore()
        let segment = DownloadSegment(
            index: 0,
            urlString: "https://example.com/video/0.ts",
            localFileName: "segment-0.ts"
        )
        job.segments = [segment]
        defer {
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        try Data(repeating: 0x47, count: 10).write(to: fileStore.segmentURL(for: segment, job: job))
        try Data(repeating: 0x00, count: 5).write(to: try fileStore.intermediateTSURL(for: job))

        let usage = StorageUsageCalculator().usage(for: job)

        #expect(usage.byteCount == 15)
    }

    @Test @MainActor func storageUsageDoesNotDoubleCountFinalMediaInsideTaskDirectory() throws {
        let job = DownloadJob(
            title: "Internal Final",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Internal Final"
        )
        let fileStore = DownloadFileStore()
        defer {
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        let finalURL = try fileStore.finalMediaURL(for: job)
        try Data(repeating: 0x00, count: 8).write(to: finalURL)
        job.finalFilePath = finalURL.path(percentEncoded: false)

        let usage = StorageUsageCalculator().usage(for: job)

        #expect(usage.byteCount == 8)
    }

    @Test @MainActor func storageUsageIncludesExternalFinalMedia() throws {
        let externalURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        let job = DownloadJob(
            title: "External Final",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "External Final"
        )
        let fileStore = DownloadFileStore()
        defer {
            try? FileManager.default.removeItem(at: externalURL)
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        try Data(repeating: 0x00, count: 12).write(to: externalURL)
        job.finalFilePath = externalURL.path(percentEncoded: false)

        let usage = StorageUsageCalculator().usage(for: job)

        #expect(usage.byteCount == 12)
    }

    @Test @MainActor func storageUsageIgnoresMissingFiles() {
        let job = DownloadJob(
            title: "Missing Files",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Missing Files"
        )
        job.finalFilePath = "/missing/\(UUID().uuidString).mp4"

        let usage = StorageUsageCalculator().usage(for: job)

        #expect(usage.byteCount == 0)
    }

    @Test @MainActor func storageSortsNewestFirst() {
        let older = DownloadJob(
            title: "Older",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Older"
        )
        let newer = DownloadJob(
            title: "Newer",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Newer"
        )
        older.createdAt = Date(timeIntervalSince1970: 100)
        newer.createdAt = Date(timeIntervalSince1970: 200)

        let sorted = StorageUsageSorter.sorted([
            StorageUsage(job: older, byteCount: 20),
            StorageUsage(job: newer, byteCount: 10)
        ], by: .newestFirst)

        #expect(sorted.map(\.job.title) == ["Newer", "Older"])
    }

    @Test @MainActor func storageSortsLargestFirst() {
        let smaller = DownloadJob(
            title: "Smaller",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Smaller"
        )
        let larger = DownloadJob(
            title: "Larger",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Larger"
        )
        smaller.createdAt = Date(timeIntervalSince1970: 200)
        larger.createdAt = Date(timeIntervalSince1970: 100)

        let sorted = StorageUsageSorter.sorted([
            StorageUsage(job: smaller, byteCount: 10),
            StorageUsage(job: larger, byteCount: 20)
        ], by: .largestFirst)

        #expect(sorted.map(\.job.title) == ["Larger", "Smaller"])
    }

    @Test @MainActor func deletingAllRecordAndFileRemovesJobsAndTaskDirectories() throws {
        let schema = Schema([DownloadJob.self, DownloadSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let suiteName = "M3U8DownloaderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let jobs = [
            DownloadJob(title: "First", sourceURLString: "https://example.com/video/index.m3u8", outputFileName: "First"),
            DownloadJob(title: "Second", sourceURLString: "https://example.com/video/index.m3u8", outputFileName: "Second")
        ]
        let fileStore = DownloadFileStore()
        for job in jobs {
            container.mainContext.insert(job)
            let directory = try fileStore.taskDirectory(for: job)
            try Data([0x47]).write(to: directory.appending(path: "segment.ts"))
        }

        let engine = DownloadEngine(
            modelContext: container.mainContext,
            settings: SettingsStore(defaults: defaults, keychain: .shared)
        )
        engine.delete(jobs, mode: .recordAndFile)

        for job in jobs {
            #expect(!FileManager.default.fileExists(atPath: fileStore.taskDirectoryURL(for: job).path(percentEncoded: false)))
        }
        let descriptor = FetchDescriptor<DownloadJob>()
        #expect(try container.mainContext.fetch(descriptor).isEmpty)
    }

#if os(macOS)
    @Test @MainActor func deletingAllRecordOnlyPreservesExternalFinalMedia() throws {
        let schema = Schema([DownloadJob.self, DownloadSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let suiteName = "M3U8DownloaderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let externalURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: externalURL)
        }

        let job = DownloadJob(
            title: "External Preserved",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "External Preserved"
        )
        job.status = .completed
        job.finalFilePath = externalURL.path(percentEncoded: false)
        container.mainContext.insert(job)

        let fileStore = DownloadFileStore()
        let directory = try fileStore.taskDirectory(for: job)
        try Data([0x47]).write(to: directory.appending(path: "segment.ts"))
        try Data([0x00]).write(to: externalURL)

        let engine = DownloadEngine(
            modelContext: container.mainContext,
            settings: SettingsStore(defaults: defaults, keychain: .shared)
        )
        engine.delete([job], mode: .recordOnly)

        #expect(FileManager.default.fileExists(atPath: externalURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }
#endif

#if os(macOS)
    @Test @MainActor func macOSAssemblyCleanupRemovesSegmentsAndKeepsAppStoredMP4() throws {
        let job = DownloadJob(
            title: "Internal MP4",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Internal MP4"
        )
        let fileStore = DownloadFileStore()
        let segment = DownloadSegment(
            index: 0,
            urlString: "https://example.com/video/0.ts",
            localFileName: "segment-0.ts"
        )
        job.segments = [segment]
        try Data([0x47]).write(to: fileStore.segmentURL(for: segment, job: job))
        let intermediateURL = try fileStore.intermediateTSURL(for: job)
        try Data([0x47]).write(to: intermediateURL)
        let finalURL = try fileStore.finalMediaURL(for: job)
        try Data([0x00, 0x00, 0x00]).write(to: finalURL)
        defer {
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        try fileStore.removeAssemblyWorkingFiles(for: job, preserving: finalURL)

        #expect(FileManager.default.fileExists(atPath: finalURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: fileStore.taskDirectoryURL(for: job).appending(path: "Segments").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: intermediateURL.path(percentEncoded: false)))
    }

    @Test @MainActor func macOSAssemblyCleanupRemovesTaskDirectoryForExternalMP4() throws {
        let externalURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        let job = DownloadJob(
            title: "External MP4",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "External MP4",
            destinationPath: externalURL.path(percentEncoded: false)
        )
        let fileStore = DownloadFileStore()
        let segment = DownloadSegment(
            index: 0,
            urlString: "https://example.com/video/0.ts",
            localFileName: "segment-0.ts"
        )
        job.segments = [segment]
        try Data([0x47]).write(to: fileStore.segmentURL(for: segment, job: job))
        try Data([0x00, 0x00, 0x00]).write(to: externalURL)
        defer {
            try? FileManager.default.removeItem(at: externalURL)
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        try fileStore.removeAssemblyWorkingFiles(for: job, preserving: externalURL)

        #expect(FileManager.default.fileExists(atPath: externalURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: fileStore.taskDirectoryURL(for: job).path(percentEncoded: false)))
    }

    @Test @MainActor func deletingWithUnresolvableDestinationBookmarkStillRemovesTaskDirectory() throws {
        let schema = Schema([DownloadJob.self, DownloadSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let suiteName = "M3U8DownloaderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let job = DownloadJob(
            title: "Deleted Export",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Deleted Export",
            destinationPath: "/tmp/Deleted Export.mp4",
            destinationBookmark: Data([0x00])
        )
        job.status = .completed
        job.finalFilePath = "/tmp/Deleted Export.mp4"
        container.mainContext.insert(job)

        let fileStore = DownloadFileStore()
        let taskDirectory = try fileStore.taskDirectory(for: job)
        try Data([0x47]).write(to: taskDirectory.appending(path: "orphan.ts"))

        let engine = DownloadEngine(
            modelContext: container.mainContext,
            settings: SettingsStore(defaults: defaults, keychain: .shared)
        )
        engine.delete(job, mode: .recordAndFile)

        #expect(!FileManager.default.fileExists(atPath: taskDirectory.path(percentEncoded: false)))
    }
#endif

#if os(iOS) && RUN_MUX_HLS_INTEGRATION_TESTS
    private func playerItemStatus(for playerItem: AVPlayerItem) async throws -> AVPlayerItem.Status {
        switch playerItem.status {
        case .readyToPlay:
            return .readyToPlay
        case .failed:
            throw playerItem.error ?? DownloadError.fileAssemblyFailed
        case .unknown:
            break
        @unknown default:
            throw DownloadError.fileAssemblyFailed
        }

        return try await withThrowingTaskGroup(of: AVPlayerItem.Status.self) { group in
            group.addTask {
                for await status in playerItem.publisher(for: \.status).values {
                    switch status {
                    case .readyToPlay:
                        return status
                    case .failed:
                        throw playerItem.error ?? DownloadError.fileAssemblyFailed
                    case .unknown:
                        continue
                    @unknown default:
                        throw DownloadError.fileAssemblyFailed
                    }
                }
                throw DownloadError.fileAssemblyFailed
            }
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw playerItem.error ?? DownloadError.fileAssemblyFailed
            }

            let status = try await group.next() ?? .unknown
            group.cancelAll()
            return status
        }
    }
#endif

    @Test func mediaPlaylistParsesRelativeSegmentsAndAESKey() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-KEY:METHOD=AES-128,URI="keys/video.key",IV=0x0000000000000000000000000000000a
        #EXTINF:4.0,
        segment-1.ts
        #EXTINF:5.5,
        nested/segment-2.ts
        #EXT-X-ENDLIST
        """

        let result = try HLSPlaylistParser().parse(
            text: playlist,
            sourceURL: URL(string: "https://example.com/path/index.m3u8")!
        )

        #expect(result.segments.count == 2)
        #expect(result.segments[0].url.absoluteString == "https://example.com/path/segment-1.ts")
        #expect(result.segments[1].url.absoluteString == "https://example.com/path/nested/segment-2.ts")
        #expect(result.segments[0].encryption?.method == "AES-128")
        #expect(result.segments[0].encryption?.keyURL.absoluteString == "https://example.com/path/keys/video.key")
    }

    @Test func masterPlaylistChoosesHighestBandwidthVariant() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720
        low/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080
        high/index.m3u8
        """

        let result = try HLSPlaylistParser().parse(
            text: playlist,
            sourceURL: URL(string: "https://example.com/master.m3u8")!
        )

        #expect(result.variant?.url.absoluteString == "https://example.com/high/index.m3u8")
        #expect(result.variant?.bandwidth == 4_000_000)
    }

    @Test func mediaPlaylistParsesByteRanges() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:4
        #EXTINF:10.0,
        #EXT-X-BYTERANGE:100@0
        main.ts
        #EXTINF:10.0,
        #EXT-X-BYTERANGE:120
        main.ts
        """

        let result = try HLSPlaylistParser().parse(
            text: playlist,
            sourceURL: URL(string: "https://example.com/video/prog_index.m3u8")!
        )

        #expect(result.segments.count == 2)
        #expect(result.segments[0].url.absoluteString == "https://example.com/video/main.ts")
        #expect(result.segments[0].byteRange == HLSByteRange(length: 100, offset: 0))
        #expect(result.segments[1].byteRange == HLSByteRange(length: 120, offset: 100))
    }

    @Test func mediaPlaylistParsesFMP4InitializationSegment() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-MAP:URI="init/stream.m4s",BYTERANGE="720@0"
        #EXTINF:6.0,
        media/stream-1.m4s
        #EXTINF:6.0,
        media/stream-2.m4s
        #EXT-X-ENDLIST
        """

        let result = try HLSPlaylistParser().parse(
            text: playlist,
            sourceURL: URL(string: "https://example.com/video/index.m3u8")!
        )

        let initializationSegment = try #require(result.segments[0].initializationSegment)
        #expect(initializationSegment.url.absoluteString == "https://example.com/video/init/stream.m4s")
        #expect(initializationSegment.byteRange == HLSByteRange(length: 720, offset: 0))
        #expect(result.segments[1].initializationSegment == initializationSegment)
    }

    @Test func localFileNamingPreservesMediaContainerExtensions() throws {
        let fMP4URL = try #require(URL(string: "https://example.com/media/818a_1.m4s?token=redacted"))
        let transportStreamURL = try #require(URL(string: "https://example.com/media/segment.ts"))

        #expect(HLSLocalFileNaming.mediaSegmentFileName(index: 1, url: fMP4URL, hasInitializationSegment: true) == "segment-1.m4s")
        #expect(HLSLocalFileNaming.initializationSegmentFileName(index: 0, url: fMP4URL) == "init-0.m4s")
        #expect(HLSLocalFileNaming.mediaSegmentFileName(index: 2, url: transportStreamURL, hasInitializationSegment: false) == "segment-2.ts")
    }

    @Test @MainActor func legacyFMP4TaskRequiresPlaylistRefreshBeforeRetry() {
        let job = DownloadJob(
            title: "Legacy Fragmented MP4",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Legacy Fragmented MP4"
        )
        job.segments = [
            DownloadSegment(
                index: 0,
                urlString: "https://example.com/video/segment-0.m4s",
                localFileName: "segment-0.ts"
            )
        ]

        #expect(job.requiresFMP4PlaylistRefresh)

        job.segments.append(
            DownloadSegment(
                index: 0,
                urlString: "https://example.com/video/init.m4s",
                localFileName: "init-0.m4s",
                kind: .initialization
            )
        )
        #expect(!job.requiresFMP4PlaylistRefresh)
    }

    @Test @MainActor func fMP4ResourcesProduceMapPlaylistAndInitializeBeforeMedia() throws {
        let job = DownloadJob(
            title: "Fragmented MP4",
            sourceURLString: "https://example.com/video/index.m3u8",
            outputFileName: "Fragmented MP4"
        )
        let initializationSegment = DownloadSegment(
            index: 0,
            urlString: "https://example.com/video/init.m4s",
            localFileName: "init-0.m4s",
            kind: .initialization
        )
        let mediaSegment = DownloadSegment(
            index: 0,
            urlString: "https://example.com/video/segment.m4s",
            localFileName: "segment-0.m4s",
            duration: 6
        )
        job.segments = [mediaSegment, initializationSegment]

        let fileStore = DownloadFileStore()
        let outputURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: fileStore.taskDirectoryURL(for: job))
        }

        try Data([0x01, 0x02]).write(to: fileStore.segmentURL(for: initializationSegment, job: job))
        try Data([0x03, 0x04]).write(to: fileStore.segmentURL(for: mediaSegment, job: job))
        guard FileManager.default.createFile(atPath: outputURL.fileSystemPath, contents: nil) else {
            Issue.record("Could not create the intermediate output file")
            return
        }

        let assembler = MediaAssembler()
        try assembler.writeResources(for: job, to: outputURL)
        let localPlaylist = try assembler.hlsPlaylist(for: job)

        #expect(try Data(contentsOf: outputURL) == Data([0x01, 0x02, 0x03, 0x04]))
        #expect(localPlaylist.localizedStandardContains("#EXT-X-MAP:URI=\"Segments/init-0.m4s\""))
        #expect(localPlaylist.localizedStandardContains("Segments/segment-0.m4s"))
    }

    @Test func fileNameSanitizerRemovesInvalidCharacters() {
        #expect("a/b:c*?".sanitizedFileName == "a-b-c")
        #expect(" \n ".sanitizedFileName == String(localized: .untitled))
    }

    @Test func addDownloadDestinationUsesTypedNameBeforeSelectedPathName() {
        let destination = AddDownloadDestination(
            urlString: "https://example.com/original.m3u8",
            outputName: "Typed Name",
            authorizedURL: URL(filePath: "/Users/example/Downloads/Panel Name.mp4")
        )

        #expect(destination.resolvedName == "Typed Name")
        #expect(destination.defaultFileName == "Typed Name.mp4")
        #expect(destination.requestedURL?.path(percentEncoded: false) == "/Users/example/Downloads/Typed Name.mp4")
    }

#if os(macOS)
    @Test func addDownloadDestinationRequiresAuthorizationWhenTypedNameChangesSelectedFile() {
        let destination = AddDownloadDestination(
            urlString: "https://example.com/original.m3u8",
            outputName: "Typed Name",
            authorizedURL: URL(filePath: "/Users/example/Downloads/Panel Name.mp4")
        )

        #expect(destination.needsAuthorization)
        #expect(destination.panelDirectoryURL?.standardizedFileURL == URL(filePath: "/Users/example/Downloads", directoryHint: .isDirectory).standardizedFileURL)
    }

    @Test func addDownloadDestinationDoesNotRequireAuthorizationWhenTypedNameMatchesSelectedFile() {
        let destination = AddDownloadDestination(
            urlString: "https://example.com/original.m3u8",
            outputName: "Panel Name",
            authorizedURL: URL(filePath: "/Users/example/Downloads/Panel Name.mp4")
        )

        #expect(!destination.needsAuthorization)
        #expect(destination.requestedURL?.path(percentEncoded: false) == "/Users/example/Downloads/Panel Name.mp4")
    }
#endif

    @Test @MainActor func settingsUseDefaultsWhenNoUserDefaultsExist() {
        let suiteName = "M3U8DownloaderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsStore(defaults: defaults, keychain: .shared)

        #expect(settings.concurrencyLimit == 6)
        #expect(settings.retryLimit == 3)
        #expect(settings.timeoutSeconds == 30)
        #expect(settings.proxyConfiguration == .disabled)
    }

    @Test @MainActor func demoJobsCoverScreenshotStatesWithoutPersistence() {
        let jobs = PreviewSamples.demoJobs
        let statuses = Set(jobs.map(\.status))

        #expect(jobs.count >= 5)
        #expect(statuses.contains(.queued))
        #expect(statuses.contains(.downloading))
        #expect(statuses.contains(.paused))
        #expect(statuses.contains(.completed))
        #expect(statuses.contains(.failed))
        #expect(jobs.allSatisfy { !$0.title.isEmpty && !$0.sourceURLString.isEmpty })
    }

    @Test @MainActor func appLaunchConfigurationUsesDemoModeArgument() {
        let configuration = AppLaunchConfiguration(arguments: ["M3U8 Downloader", "--demo-mode"], environment: [:])

        #expect(configuration.runtimeMode == .demo)
    }

    @Test @MainActor func appLaunchConfigurationUsesDemoModeEnvironment() {
        let configuration = AppLaunchConfiguration(arguments: ["M3U8 Downloader"], environment: ["M3U8_DOWNLOADER_DEMO_MODE": "true"])

        #expect(configuration.runtimeMode == .demo)
    }

    @Test @MainActor func demoDownloadEngineDoesNotMutateJobs() throws {
        let container = PreviewSamples.modelContainer()
        let suiteName = "M3U8DownloaderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let settings = SettingsStore(defaults: defaults, keychain: .shared)
        let job = PreviewSamples.failedJob
        container.mainContext.insert(job)
        try container.mainContext.save()

        let engine = DownloadEngine(modelContext: container.mainContext, settings: settings, mode: .demo)
        engine.retry(job)
        engine.delete(job, mode: .recordAndFile)

        #expect(job.status == .failed)
        #expect(container.mainContext.model(for: job.persistentModelID) is DownloadJob)
    }

    @Test func bitrateFormatUsesHumanReadableSIUnits() {
        #expect(999.formatted(.bitrate) == "999 bps")
        #expect(128_000.formatted(.bitrate) == "128 kbps")
        #expect(4_000_000.formatted(.bitrate) == "4 Mbps")
        #expect(6_500_000.formatted(.bitrate) == "6.5 Mbps")
        #expect(1_200_000_000.formatted(.bitrate) == "1.2 Gbps")
    }
}
