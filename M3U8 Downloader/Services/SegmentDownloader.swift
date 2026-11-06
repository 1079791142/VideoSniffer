import Foundation
import SwiftData

nonisolated struct SegmentRequest: Sendable {
    var id: PersistentIdentifier
    var index: Int
    var urlString: String
    var outputURL: URL
    var retryLimit: Int
    var encryptionMethod: String?
    var keyURLString: String?
    var initializationVectorHex: String?
    var byteRangeLength: Int64?
    var byteRangeOffset: Int64?
}

nonisolated struct SegmentResult: Sendable {
    var segmentID: PersistentIdentifier
    var byteCount: Int64
    var retryCount: Int
}

nonisolated struct SegmentDownloader: Sendable {
    let configuration: URLSessionConfiguration

    func download(_ request: SegmentRequest) async throws -> SegmentResult {
        guard let url = URL(string: request.urlString) else {
            throw DownloadError.invalidURL
        }

        let session = URLSession(configuration: configuration)
        var attempt = 0
        var lastError: Error?

        while attempt <= request.retryLimit {
            do {
                try Task.checkCancellation()
                var data = try await fetchData(
                    url: url,
                    session: session,
                    byteRangeLength: request.byteRangeLength,
                    byteRangeOffset: request.byteRangeOffset
                )
                if request.encryptionMethod == "AES-128" {
                    data = try await decrypt(data: data, request: request, session: session)
                }
                try data.write(to: request.outputURL, options: [.atomic])
                return SegmentResult(segmentID: request.id, byteCount: Int64(data.count), retryCount: attempt)
            } catch {
                lastError = error
                if Task.isCancelled {
                    throw error
                }
                if attempt >= request.retryLimit {
                    break
                }
                attempt += 1
                try await Task.sleep(for: .milliseconds(250 * Int(pow(2.0, Double(min(attempt, 5))))))
            }
        }

        throw lastError ?? DownloadError.invalidResponse(url)
    }

    private func fetchData(
        url: URL,
        session: URLSession,
        byteRangeLength: Int64? = nil,
        byteRangeOffset: Int64? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        if let byteRangeLength, let byteRangeOffset {
            let endOffset = byteRangeOffset + byteRangeLength - 1
            request.setValue("bytes=\(byteRangeOffset)-\(endOffset)", forHTTPHeaderField: "Range")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse(url)
        }
        if byteRangeLength != nil || byteRangeOffset != nil {
            guard httpResponse.statusCode == 206 else {
                throw DownloadError.httpStatus(httpResponse.statusCode, url)
            }
        } else if !(200..<300).contains(httpResponse.statusCode) {
            throw DownloadError.httpStatus(httpResponse.statusCode, url)
        }
        return data
    }

    private func decrypt(data: Data, request: SegmentRequest, session: URLSession) async throws -> Data {
        guard let keyURLString = request.keyURLString, let keyURL = URL(string: keyURLString) else {
            throw HLSPlaylistError.missingKeyURI
        }
        let key = try await fetchData(url: keyURL, session: session)
        let iv = request.initializationVectorHex.flatMap(HLSPlaylistParser.hexData) ?? defaultIV(for: request.index)
        return try AES128Decryptor().decrypt(data: data, key: key, initializationVector: iv)
    }

    private func defaultIV(for index: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        var value = UInt64(index)
        for position in stride(from: 15, through: 8, by: -1) {
            bytes[position] = UInt8(value & 0xff)
            value >>= 8
        }
        return Data(bytes)
    }
}
