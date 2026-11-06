import Foundation

nonisolated struct AddDownloadDestination {
    var urlString: String
    var outputName: String
    var authorizedURL: URL?

    var defaultFileName: String {
        "\(resolvedName.sanitizedFileName).mp4"
    }

    var resolvedName: String {
        let name = outputName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }

        if let destinationName = authorizedURL?.deletingPathExtension().lastPathComponent, !destinationName.isEmpty {
            return destinationName
        }

        return URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))?.deletingPathExtension().lastPathComponent ?? String(localized: .download)
    }

    var requestedURL: URL? {
#if os(macOS)
        guard let authorizedURL else {
            return nil
        }

        return panelDirectoryURL?.appending(path: defaultFileName) ?? authorizedURL
#else
        nil
#endif
    }

#if os(macOS)
    var needsAuthorization: Bool {
        guard let authorizedURL, let requestedURL else {
            return false
        }

        return authorizedURL.standardizedFileURL.path(percentEncoded: false) != requestedURL.standardizedFileURL.path(percentEncoded: false)
    }

    var panelDirectoryURL: URL? {
        guard let authorizedURL else {
            return nil
        }

        if authorizedURL.pathExtension.isEmpty {
            return authorizedURL
        }

        return authorizedURL.deletingLastPathComponent()
    }
#endif
}
