import Foundation

struct DownloadFileStore: Sendable {
    var baseDirectory: URL {
        URL.documentsDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    func taskDirectoryURL(for job: DownloadJob) -> URL {
        baseDirectory.appending(path: job.tempDirectoryName, directoryHint: .isDirectory)
    }

    func taskDirectory(for job: DownloadJob) throws -> URL {
        let directory = taskDirectoryURL(for: job)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func segmentsDirectory(for job: DownloadJob) throws -> URL {
        let directory = try taskDirectory(for: job).appending(path: "Segments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func segmentURL(for segment: DownloadSegment, job: DownloadJob) throws -> URL {
        try segmentsDirectory(for: job).appending(path: segment.localFileName)
    }

    func intermediateTSURL(for job: DownloadJob) throws -> URL {
        try taskDirectory(for: job).appending(path: transportStreamFileName(for: job))
    }

    func intermediateMediaURL(for job: DownloadJob) throws -> URL {
        if job.segments.contains(where: \DownloadSegment.isInitializationSegment) {
            return try taskDirectory(for: job).appending(path: "media.mp4")
        }
        return try intermediateTSURL(for: job)
    }

    func finalMediaURL(for job: DownloadJob) throws -> URL {
#if os(macOS)
        try destinationMP4URL(for: job)
#else
        try taskDirectory(for: job).appending(path: "\(job.outputFileName).m3u8")
#endif
    }

#if os(macOS)
    func destinationMP4URL(for job: DownloadJob) throws -> URL {
        if let destinationPath = job.destinationPath {
            let url = URL(filePath: destinationPath)
            if url.pathExtension.isEmpty {
                return url.appending(path: "\(job.outputFileName).mp4")
            }
            return url
        }
        return try appStorageMP4URL(for: job)
    }
#endif

    func removeFiles(for job: DownloadJob, includingDownloadedFile: Bool) throws {
        var removalError: Error?

        if includingDownloadedFile {
            do {
                try removeFinalMediaFile(for: job)
            } catch {
                removalError = error
            }
        }

        do {
            try removeTaskDirectory(for: job)
        } catch {
            removalError = removalError ?? error
        }

        if let removalError {
            throw removalError
        }
    }

    func removeFinalMediaFile(for job: DownloadJob) throws {
        guard let finalFileURL = job.finalFilePath.map({ URL(filePath: $0) }),
              FileManager.default.fileExists(atPath: finalFileURL.fileSystemPath) else {
            return
        }

        try FileManager.default.removeItem(at: finalFileURL)
    }

    func removeTaskDirectory(for job: DownloadJob) throws {
        let taskDirectory = taskDirectoryURL(for: job)
        guard FileManager.default.fileExists(atPath: taskDirectory.fileSystemPath) else {
            return
        }

        try FileManager.default.removeItem(at: taskDirectory)
    }

    func removeAssemblyWorkingFiles(for job: DownloadJob, preserving finalMediaURL: URL) throws {
        let taskDirectory = taskDirectoryURL(for: job)
        guard FileManager.default.fileExists(atPath: taskDirectory.fileSystemPath) else {
            return
        }

        let segmentsDirectory = taskDirectory.appending(path: "Segments", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: segmentsDirectory.fileSystemPath) {
            try FileManager.default.removeItem(at: segmentsDirectory)
        }

        let intermediateURL = taskDirectory.appending(path: transportStreamFileName(for: job))
        if FileManager.default.fileExists(atPath: intermediateURL.fileSystemPath) {
            try FileManager.default.removeItem(at: intermediateURL)
        }

        let fragmentedMP4URL = taskDirectory.appending(path: "media.mp4")
        if FileManager.default.fileExists(atPath: fragmentedMP4URL.fileSystemPath) {
            try FileManager.default.removeItem(at: fragmentedMP4URL)
        }

        if !finalMediaURL.isStored(in: taskDirectory), isDirectoryEmpty(taskDirectory) {
            try FileManager.default.removeItem(at: taskDirectory)
        }
    }

    private func transportStreamFileName(for job: DownloadJob) -> String {
#if os(iOS)
        "media.ts"
#else
        "\(job.outputFileName).ts"
#endif
    }

    private func appStoredFinalMediaFileName(for job: DownloadJob) -> String {
#if os(macOS)
        "\(job.outputFileName).mp4"
#else
        "\(job.outputFileName).m3u8"
#endif
    }

#if os(macOS)
    private func appStorageMP4URL(for job: DownloadJob) throws -> URL {
        try taskDirectory(for: job).appending(path: appStoredFinalMediaFileName(for: job))
    }
#endif
}

private func isDirectoryEmpty(_ directory: URL) -> Bool {
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ) else {
        return false
    }
    return contents.isEmpty
}
