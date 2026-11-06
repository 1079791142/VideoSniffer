import Foundation

struct StorageUsage: Identifiable {
    let job: DownloadJob
    let byteCount: Int64

    var id: UUID {
        job.id
    }
}

struct StorageUsageCalculator {
    private let fileStore: DownloadFileStore
    private let fileManager: FileManager

    init(fileStore: DownloadFileStore = DownloadFileStore(), fileManager: FileManager = .default) {
        self.fileStore = fileStore
        self.fileManager = fileManager
    }

    func usage(for job: DownloadJob) -> StorageUsage {
        let taskDirectory = fileStore.taskDirectoryURL(for: job)
        let taskDirectorySize = sizeOfItem(at: taskDirectory)
        let finalMediaSize = finalMediaSize(for: job, excluding: taskDirectory)
        return StorageUsage(job: job, byteCount: taskDirectorySize + finalMediaSize)
    }

    private func finalMediaSize(for job: DownloadJob, excluding taskDirectory: URL) -> Int64 {
        guard let finalFilePath = job.finalFilePath else {
            return 0
        }

        let finalURL = URL(filePath: finalFilePath)
        guard !finalURL.isStored(in: taskDirectory) else {
            return 0
        }

#if os(macOS)
        return withSecurityScopedAccess(bookmarkData: job.destinationBookmark) {
            sizeOfItem(at: finalURL)
        }
#else
        return sizeOfItem(at: finalURL)
#endif
    }

    private func sizeOfItem(at url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.fileSystemPath) else {
            return 0
        }

        if isDirectory(url) {
            return directorySize(at: url)
        }

        return fileSize(at: url)
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard isRegularFile(fileURL) else {
                continue
            }
            total += fileSize(at: fileURL)
        }
        return total
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func fileSize(at url: URL) -> Int64 {
        let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(fileSize ?? 0)
    }
}

enum StorageSort: String, CaseIterable, Identifiable {
    case newestFirst
    case largestFirst

    var id: Self {
        self
    }
}

struct StorageUsageSorter {
    static func sorted(_ usage: [StorageUsage], by sort: StorageSort) -> [StorageUsage] {
        switch sort {
        case .newestFirst:
            usage.sorted {
                if $0.job.createdAt != $1.job.createdAt {
                    return $0.job.createdAt > $1.job.createdAt
                }
                return $0.job.title.localizedStandardCompare($1.job.title) == .orderedAscending
            }
        case .largestFirst:
            usage.sorted {
                if $0.byteCount != $1.byteCount {
                    return $0.byteCount > $1.byteCount
                }
                if $0.job.createdAt != $1.job.createdAt {
                    return $0.job.createdAt > $1.job.createdAt
                }
                return $0.job.title.localizedStandardCompare($1.job.title) == .orderedAscending
            }
        }
    }
}

extension URL {
    var fileSystemPath: String {
        path(percentEncoded: false)
    }

    func isStored(in directory: URL) -> Bool {
        standardizedFileURL.pathComponents.starts(with: directory.standardizedFileURL.pathComponents)
    }
}
