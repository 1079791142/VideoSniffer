import Foundation

nonisolated enum HLSLocalFileNaming {
    static func mediaSegmentFileName(index: Int, url: URL, hasInitializationSegment: Bool) -> String {
        let fallbackExtension = hasInitializationSegment ? "m4s" : "ts"
        return "segment-\(index).\(fileExtension(for: url, fallback: fallbackExtension))"
    }

    static func initializationSegmentFileName(index: Int, url: URL) -> String {
        "init-\(index).\(fileExtension(for: url, fallback: "mp4"))"
    }

    private static func fileExtension(for url: URL, fallback: String) -> String {
        let sourceExtension = url.pathExtension.lowercased()
        guard !sourceExtension.isEmpty,
              sourceExtension.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return fallback
        }
        return sourceExtension
    }
}
