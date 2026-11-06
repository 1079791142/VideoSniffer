import Foundation
import Observation
import SwiftData

enum DownloadDeletionMode {
    case recordOnly
    case recordAndFile
}

@MainActor
@Observable
final class DownloadEngine {
    private let modelContext: ModelContext
    private let settings: SettingsStore
    private let mode: DownloadRuntimeMode
    private let fileStore = DownloadFileStore()
    private let parser = HLSPlaylistParser()
    private let assembler = MediaAssembler()
    private var activeTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    init(modelContext: ModelContext, settings: SettingsStore, mode: DownloadRuntimeMode = .normal) {
        self.modelContext = modelContext
        self.settings = settings
        self.mode = mode
    }

    var activeJobIDs: Set<PersistentIdentifier> {
        Set(activeTasks.keys)
    }

    func addJob(sourceURLString: String, outputName: String, destinationURL: URL?) throws {
        guard mode == .normal else { return }
        guard let url = URL(string: sourceURLString), url.scheme != nil else {
            throw DownloadError.invalidURL
        }

#if os(macOS)
        let bookmark = try destinationURL.map { destinationURL in
            let bookmarkURL = try securityScopedBookmarkURL(for: destinationURL)
            return try bookmarkURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
#else
        let bookmark = try destinationURL?.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
#endif
        let title = outputName.sanitizedFileName
        let job = DownloadJob(
            title: title,
            sourceURLString: url.absoluteString,
            outputFileName: title,
            destinationPath: destinationURL?.path(percentEncoded: false),
            destinationBookmark: bookmark
        )
        modelContext.insert(job)
        try modelContext.save()
        start(job)
    }

    func start(_ job: DownloadJob) {
        guard mode == .normal else { return }
        guard activeTasks[job.persistentModelID] == nil else { return }
        job.errorMessage = nil
        if job.status != .paused {
            job.status = .queued
        }
        saveContext()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(jobID: job.persistentModelID)
        }
        activeTasks[job.persistentModelID] = task
    }

    func pause(_ job: DownloadJob) {
        guard mode == .normal else { return }
        activeTasks[job.persistentModelID]?.cancel()
        activeTasks[job.persistentModelID] = nil
        job.status = .paused
        for segment in job.segments where segment.status == .downloading {
            segment.status = .pending
        }
        saveContext()
    }

    func retry(_ job: DownloadJob) {
        guard mode == .normal else { return }
        for segment in job.segments where segment.status == .failed {
            segment.status = .pending
            segment.errorMessage = nil
        }
        job.errorMessage = nil
        start(job)
    }

    func cancel(_ job: DownloadJob) {
        guard mode == .normal else { return }
        activeTasks[job.persistentModelID]?.cancel()
        activeTasks[job.persistentModelID] = nil
        job.status = .canceled
        saveContext()
    }

    func delete(_ job: DownloadJob, mode: DownloadDeletionMode) {
        guard self.mode == .normal else { return }
        activeTasks[job.persistentModelID]?.cancel()
        activeTasks[job.persistentModelID] = nil
        if mode == .recordAndFile {
            try? withSecurityScopedDestination(for: job) {
                try fileStore.removeFinalMediaFile(for: job)
            }
        }
        try? fileStore.removeTaskDirectory(for: job)
        modelContext.delete(job)
        saveContext()
    }

    func delete(_ jobs: [DownloadJob], mode: DownloadDeletionMode) {
        for job in jobs {
            delete(job, mode: mode)
        }
    }

    private func run(jobID: PersistentIdentifier) async {
        defer {
            activeTasks[jobID] = nil
        }

        guard let job = modelContext.model(for: jobID) as? DownloadJob else {
            return
        }

        do {
            try Task.checkCancellation()
            try await prepare(job)
            try Task.checkCancellation()
            try await downloadSegments(job)
            try Task.checkCancellation()
            job.status = .assembling
            saveContext()
            let finalURL = try await withSecurityScopedDestination(for: job) {
                try await assembler.assemble(job: job)
            }
            job.finalFilePath = finalURL.path(percentEncoded: false)
            job.completedAt = Date()
            job.status = .completed
            saveContext()
        } catch {
            if isCancellation(error) {
                if job.status != .canceled {
                    job.status = .paused
                }
            } else {
                job.markFailed(error.localizedDescription)
            }
            saveContext()
        }
    }

    private func prepare(_ job: DownloadJob) async throws {
        if job.requiresFMP4PlaylistRefresh {
            try? fileStore.removeTaskDirectory(for: job)
            let legacySegments = job.segments
            job.segments.removeAll()
            for segment in legacySegments {
                modelContext.delete(segment)
            }
        }

        guard job.segments.isEmpty else {
            job.status = .downloading
            saveContext()
            return
        }
        guard let url = job.sourceURL else {
            throw DownloadError.invalidURL
        }

        job.status = .preparing
        job.startedAt = job.startedAt ?? Date()
        saveContext()

        let session = URLSession(configuration: settings.makeURLSessionConfiguration())
        let playlistText = try await fetchText(url: url, session: session)
        let playlist = try await parser.parseResolved(text: playlistText, sourceURL: url) { variantURL in
            try await fetchText(url: variantURL, session: session)
        }

        job.selectedVariantResolution = playlist.variant?.resolution
        job.selectedVariantBandwidth = playlist.variant?.bandwidth
        job.segmentCount = playlist.segments.count
        job.completedSegmentCount = 0
        job.downloadedBytes = 0
        job.totalBytes = 0
        var activeInitializationSegment: HLSInitializationSegment?
        for segment in playlist.segments {
            if let initializationSegment = segment.initializationSegment,
               initializationSegment != activeInitializationSegment {
                let model = DownloadSegment(
                    index: segment.index,
                    urlString: initializationSegment.url.absoluteString,
                    localFileName: HLSLocalFileNaming.initializationSegmentFileName(
                        index: segment.index,
                        url: initializationSegment.url
                    ),
                    kind: .initialization,
                    encryptionMethod: initializationSegment.encryption?.method,
                    keyURLString: initializationSegment.encryption?.keyURL.absoluteString,
                    initializationVectorHex: initializationSegment.encryption?.initializationVector?.hexString,
                    byteRangeLength: initializationSegment.byteRange?.length,
                    byteRangeOffset: initializationSegment.byteRange?.offset
                )
                model.job = job
                job.segments.append(model)
                activeInitializationSegment = initializationSegment
            }

            let model = DownloadSegment(
                index: segment.index,
                urlString: segment.url.absoluteString,
                localFileName: HLSLocalFileNaming.mediaSegmentFileName(
                    index: segment.index,
                    url: segment.url,
                    hasInitializationSegment: segment.initializationSegment != nil
                ),
                duration: segment.duration,
                encryptionMethod: segment.encryption?.method,
                keyURLString: segment.encryption?.keyURL.absoluteString,
                initializationVectorHex: segment.encryption?.initializationVector?.hexString,
                byteRangeLength: segment.byteRange?.length,
                byteRangeOffset: segment.byteRange?.offset
            )
            model.job = job
            job.segments.append(model)
        }

        job.status = .downloading
        saveContext()
    }

    private func downloadSegments(_ job: DownloadJob) async throws {
        job.status = .downloading
        saveContext()

        let pendingSegments = job.segments
            .filter { $0.status != .completed }
            .sorted(by: { $0.index < $1.index })
        guard !pendingSegments.isEmpty else {
            return
        }

        let configuration = settings.makeURLSessionConfiguration()
        let retryLimit = settings.retryLimit
        let concurrencyLimit = settings.concurrencyLimit
        let jobDirectory = try fileStore.segmentsDirectory(for: job)

        try Task.checkCancellation()
        try await withThrowingTaskGroup(of: SegmentResult.self) { group in
            var nextSegmentIndex = 0
            var inFlightSegmentIDs = Set<PersistentIdentifier>()

            func enqueueNextSegment() {
                guard nextSegmentIndex < pendingSegments.count else {
                    return
                }

                let segment = pendingSegments[nextSegmentIndex]
                nextSegmentIndex += 1
                segment.status = .downloading
                segment.errorMessage = nil
                inFlightSegmentIDs.insert(segment.persistentModelID)

                let request = SegmentRequest(
                    id: segment.persistentModelID,
                    index: segment.index,
                    urlString: segment.urlString,
                    outputURL: jobDirectory.appending(path: segment.localFileName),
                    retryLimit: retryLimit,
                    encryptionMethod: segment.encryptionMethod,
                    keyURLString: segment.keyURLString,
                    initializationVectorHex: segment.initializationVectorHex,
                    byteRangeLength: segment.byteRangeLength,
                    byteRangeOffset: segment.byteRangeOffset
                )
                group.addTask {
                    try await SegmentDownloader(configuration: configuration).download(request)
                }
            }

            for _ in 0..<min(concurrencyLimit, pendingSegments.count) {
                enqueueNextSegment()
            }
            saveContext()

            do {
                while let result = try await group.next() {
                    try Task.checkCancellation()
                    inFlightSegmentIDs.remove(result.segmentID)
                    if let segment = modelContext.model(for: result.segmentID) as? DownloadSegment {
                        segment.status = .completed
                        segment.byteCount = result.byteCount
                        segment.retryCount = result.retryCount
                        segment.errorMessage = nil
                    }

                    recalculateProgress(job)
                    enqueueNextSegment()
                    saveContext()
                }
            } catch {
                for segmentID in inFlightSegmentIDs {
                    guard let segment = modelContext.model(for: segmentID) as? DownloadSegment,
                          segment.status == .downloading else {
                        continue
                    }

                    if isCancellation(error) {
                        segment.status = .pending
                        segment.errorMessage = nil
                    } else {
                        segment.status = .failed
                        segment.errorMessage = error.localizedDescription
                    }
                }
                saveContext()
                throw error
            }
        }
    }

    private func fetchText(url: URL, session: URLSession) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse(url)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadError.httpStatus(httpResponse.statusCode, url)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func recalculateProgress(_ job: DownloadJob) {
        job.completedSegmentCount = job.segments.filter {
            !$0.isInitializationSegment && $0.status == .completed
        }.count
        job.downloadedBytes = job.segments.reduce(0) { $0 + $1.byteCount }
        job.updatedAt = Date()
    }

    private func saveContext() {
        try? modelContext.save()
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }

#if os(macOS)
    private func securityScopedBookmarkURL(for destinationURL: URL) throws -> URL {
        let isDirectory = (try? destinationURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isDirectory {
            return destinationURL
        }
        if !FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try Data().write(to: destinationURL, options: .withoutOverwriting)
        }
        return destinationURL
    }
#endif

    private func withSecurityScopedDestination<T>(for job: DownloadJob, operation: () async throws -> T) async throws -> T {
#if os(macOS)
        guard let bookmark = job.destinationBookmark else {
            return try await operation()
        }
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation()
#else
        return try await operation()
#endif
    }

    private func withSecurityScopedDestination<T>(for job: DownloadJob, operation: () throws -> T) throws -> T {
#if os(macOS)
        guard let bookmark = job.destinationBookmark else {
            return try operation()
        }
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
#else
        return try operation()
#endif
    }
}
