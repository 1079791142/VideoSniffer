#if os(iOS)
import Foundation
import Network

nonisolated final class LocalHLSServer: @unchecked Sendable {
    private let listener: NWListener
    private let rootDirectory: URL
    private let playlistFileName: String
    private let queue = DispatchQueue(label: "LocalHLSServer")
    private let activeConnections = LockedConnections()
    private let startState = LockedStartState()

    init(rootDirectory: URL, playlistFileName: String) throws {
        self.rootDirectory = rootDirectory
        self.playlistFileName = playlistFileName
        self.listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [startState] state in
            switch state {
            case .ready:
                startState.resume(with: .success(()))
            case .failed(let error):
                startState.resume(with: .failure(error))
            case .cancelled:
                startState.resume(with: .failure(DownloadError.canceled))
            default:
                break
            }
        }

        try await withCheckedThrowingContinuation { continuation in
            startState.set(continuation)
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        activeConnections.cancelAll()
    }

    func playlistURL() throws -> URL {
        guard let port = listener.port, port.rawValue != 0 else {
            throw DownloadError.fileAssemblyFailed
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port.rawValue)
        components.path = "/" + playlistFileName
        guard let url = components.url else {
            throw DownloadError.fileAssemblyFailed
        }
        return url
    }

    private func handle(_ connection: NWConnection) {
        activeConnections.insert(connection)
        connection.stateUpdateHandler = { [activeConnections] state in
            if case .cancelled = state {
                activeConnections.remove(connection)
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, data: Data())
    }

    private func receiveRequest(on connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                self.send(status: "500 Internal Server Error", body: Data(error.localizedDescription.utf8), on: connection)
                return
            }

            var requestData = data
            if let content {
                requestData.append(content)
            }

            if requestData.contains(Data("\r\n\r\n".utf8)) || isComplete {
                self.respond(to: requestData, on: connection)
            } else {
                self.receiveRequest(on: connection, data: requestData)
            }
        }
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        guard
            let request = String(data: requestData, encoding: .utf8),
            let requestLineEnd = request.range(of: "\r\n")
        else {
            send(status: "400 Bad Request", body: Data(), on: connection)
            return
        }

        let requestLine = request[..<requestLineEnd.lowerBound]
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(status: "400 Bad Request", body: Data(), on: connection)
            return
        }

        let path = String(parts[1]).split(separator: "?").first.map(String.init) ?? "/"
        let rawFileName = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let fileName = rawFileName.removingPercentEncoding ?? rawFileName
        guard isAllowedFileName(fileName) else {
            send(status: "404 Not Found", body: Data(), on: connection)
            return
        }

        let fileURL = fileURL(for: fileName)
        do {
            let body = try Data(contentsOf: fileURL)
            let range = byteRange(from: request, bodyLength: body.count)
            send(body: body, range: range, contentType: contentType(for: fileURL), on: connection)
        } catch {
            send(status: "404 Not Found", body: Data(), on: connection)
        }
    }

    private func byteRange(from request: String, bodyLength: Int) -> Range<Int>? {
        guard
            let rangeHeaderLine = request
                .components(separatedBy: "\r\n")
                .first(where: { $0.localizedStandardContains("Range: bytes=") }),
            let rangeText = rangeHeaderLine
                .split(separator: "=")
                .last?
                .split(separator: ",")
                .first
        else {
            return nil
        }

        let bounds = rangeText.split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2 else {
            return nil
        }

        let start = Int(bounds[0]) ?? 0
        let end = bounds[1].isEmpty ? bodyLength - 1 : (Int(bounds[1]) ?? bodyLength - 1)
        guard start >= 0, end >= start, start < bodyLength else {
            return nil
        }

        return start..<min(end + 1, bodyLength)
    }

    private func send(body: Data, range: Range<Int>?, contentType: String, on connection: NWConnection) {
        guard let range else {
            send(status: "200 OK", body: body, contentType: contentType, on: connection)
            return
        }

        let rangedBody = body.subdata(in: range)
        let header = """
        HTTP/1.1 206 Partial Content\r
        Content-Length: \(rangedBody.count)\r
        Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(body.count)\r
        Accept-Ranges: bytes\r
        Content-Type: \(contentType)\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(rangedBody)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func send(status: String, body: Data, contentType: String = "application/octet-stream", on connection: NWConnection) {
        let header = """
        HTTP/1.1 \(status)\r
        Content-Length: \(body.count)\r
        Accept-Ranges: bytes\r
        Content-Type: \(contentType)\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func contentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m3u8":
            "application/vnd.apple.mpegurl"
        case "ts":
            "video/mp2t"
        case "m4s", "mp4":
            "video/mp4"
        default:
            "application/octet-stream"
        }
    }

    private func isAllowedFileName(_ fileName: String) -> Bool {
        if fileName == playlistFileName {
            return true
        }

        guard fileName.hasPrefix("Segments/") else {
            return false
        }

        let segmentFileName = String(fileName.dropFirst("Segments/".count))
        guard URL(filePath: segmentFileName).lastPathComponent == segmentFileName else {
            return false
        }
        let isKnownResource = segmentFileName.hasPrefix("segment-") || segmentFileName.hasPrefix("init-")
        let allowedExtensions = ["ts", "m4s", "mp4"]
        return isKnownResource && allowedExtensions.contains(URL(filePath: segmentFileName).pathExtension.lowercased())
    }

    private func fileURL(for fileName: String) -> URL {
        if fileName.hasPrefix("Segments/") {
            let segmentFileName = String(fileName.dropFirst("Segments/".count))
            return rootDirectory
                .appending(path: "Segments", directoryHint: .isDirectory)
                .appending(path: segmentFileName)
        }

        return rootDirectory.appending(path: fileName)
    }
}

nonisolated private final class LockedConnections: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    func insert(_ connection: NWConnection) {
        lock.withLock {
            connections.append(connection)
        }
    }

    func remove(_ connection: NWConnection) {
        lock.withLock {
            connections.removeAll { $0 === connection }
        }
    }

    func cancelAll() {
        let connectionsToCancel = lock.withLock {
            let connectionsToCancel = connections
            connections.removeAll()
            return connectionsToCancel
        }
        for connection in connectionsToCancel {
            connection.cancel()
        }
    }
}

nonisolated private final class LockedStartState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func set(_ continuation: CheckedContinuation<Void, Error>) {
        let storedResult: Result<Void, Error>? = lock.withLock {
            if let existingResult = result {
                return existingResult
            }
            self.continuation = continuation
            return nil
        }

        if let storedResult {
            continuation.resume(with: storedResult)
        }
    }

    func resume(with result: Result<Void, Error>) {
        let continuation = lock.withLock {
            guard self.result == nil else {
                return nil as CheckedContinuation<Void, Error>?
            }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        continuation?.resume(with: result)
    }
}
#endif
