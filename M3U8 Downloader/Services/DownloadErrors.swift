import Foundation

nonisolated enum DownloadError: LocalizedError {
    case invalidURL
    case jobMissing
    case canceled
    case invalidResponse(URL)
    case httpStatus(Int, URL)
    case fileAssemblyFailed
    case mp4ExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: .enterAValidM3U8Url)
        case .jobMissing:
            String(localized: .theDownloadTaskNoLongerExists)
        case .canceled:
            String(localized: .theDownloadWasCanceled)
        case .invalidResponse(let url):
            String(localized: .invalidResponseFrom(url.absoluteString))
        case .httpStatus(let status, let url):
            String(localized: .httpWhileDownloading(status, url.absoluteString))
        case .fileAssemblyFailed:
            String(localized: .couldNotAssembleTheDownloadedMediaSegments)
        case .mp4ExportFailed(let reason):
            String(localized: .couldNotExportMp4(reason))
        }
    }
}
