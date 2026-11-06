import Foundation

nonisolated struct HLSPlaylistParser: Sendable {
    func parse(text: String, sourceURL: URL) throws -> HLSPlaylist {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.first == "#EXTM3U" else {
            throw HLSPlaylistError.invalidPlaylist
        }

        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
            return try parseMaster(lines: lines, sourceURL: sourceURL)
        }
        return try parseMedia(lines: lines, sourceURL: sourceURL, variant: nil)
    }

    func parseResolved(text: String, sourceURL: URL, loader: (URL) async throws -> String) async throws -> HLSPlaylist {
        let firstPass = try parse(text: text, sourceURL: sourceURL)
        guard let variant = firstPass.variant else {
            return firstPass
        }
        let mediaText = try await loader(variant.url)
        return try parseMedia(
            lines: normalizedLines(mediaText),
            sourceURL: variant.url,
            variant: variant
        )
    }

    private func parseMaster(lines: [String], sourceURL: URL) throws -> HLSPlaylist {
        var variants: [HLSVariant] = []

        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
            guard let nextURI = lines.dropFirst(index + 1).first(where: { !$0.hasPrefix("#") }) else {
                continue
            }
            let attributes = parseAttributes(from: line)
            let bandwidth = Int(attributes["BANDWIDTH"] ?? "") ?? 0
            let resolution = attributes["RESOLUTION"]
            let url = resolve(nextURI, relativeTo: sourceURL)
            variants.append(HLSVariant(url: url, bandwidth: bandwidth, resolution: resolution))
        }

        guard let best = variants.max(by: { $0.bandwidth < $1.bandwidth }) else {
            throw HLSPlaylistError.noSegments
        }
        return HLSPlaylist(sourceURL: sourceURL, variant: best, segments: [])
    }

    private func parseMedia(lines: [String], sourceURL: URL, variant: HLSVariant?) throws -> HLSPlaylist {
        var segments: [HLSSegment] = []
        var currentDuration: Double?
        var currentEncryption: HLSEncryption?
        var currentInitializationSegment: HLSInitializationSegment?
        var pendingByteRange: PendingByteRange?
        var nextByteRangeOffsetByURL: [String: Int64] = [:]

        for line in lines {
            if line.hasPrefix("#EXTINF") {
                currentDuration = parseDuration(line)
            } else if line.hasPrefix("#EXT-X-KEY") {
                currentEncryption = try parseKey(line, sourceURL: sourceURL)
            } else if line.hasPrefix("#EXT-X-MAP") {
                currentInitializationSegment = try parseInitializationSegment(
                    line,
                    sourceURL: sourceURL,
                    encryption: currentEncryption,
                    nextByteRangeOffsetByURL: &nextByteRangeOffsetByURL
                )
            } else if line.hasPrefix("#EXT-X-BYTERANGE") {
                pendingByteRange = try parseByteRange(line)
            } else if line.hasPrefix("#") {
                continue
            } else {
                let url = resolve(line, relativeTo: sourceURL)
                let byteRange = resolvedByteRange(
                    pendingByteRange,
                    url: url,
                    nextByteRangeOffsetByURL: &nextByteRangeOffsetByURL
                )
                let segment = HLSSegment(
                    index: segments.count,
                    url: url,
                    duration: currentDuration,
                    encryption: currentEncryption,
                    byteRange: byteRange,
                    initializationSegment: currentInitializationSegment
                )
                segments.append(segment)
                currentDuration = nil
                pendingByteRange = nil
            }
        }

        guard !segments.isEmpty else {
            throw HLSPlaylistError.noSegments
        }
        return HLSPlaylist(sourceURL: sourceURL, variant: variant, segments: segments)
    }

    private func normalizedLines(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseDuration(_ line: String) -> Double? {
        guard let value = line.split(separator: ":", maxSplits: 1).last else {
            return nil
        }
        return Double(value.split(separator: ",").first ?? "")
    }

    private func parseKey(_ line: String, sourceURL: URL) throws -> HLSEncryption? {
        let attributes = parseAttributes(from: line)
        let method = attributes["METHOD"] ?? "NONE"
        if method == "NONE" {
            return nil
        }
        guard method == "AES-128" else {
            throw HLSPlaylistError.unsupportedEncryption(method)
        }
        guard let uri = attributes["URI"] else {
            throw HLSPlaylistError.missingKeyURI
        }
        return HLSEncryption(
            method: method,
            keyURL: resolve(uri, relativeTo: sourceURL),
            initializationVector: attributes["IV"].flatMap(Self.hexData)
        )
    }

    private func parseByteRange(_ line: String) throws -> PendingByteRange {
        guard let value = line.split(separator: ":", maxSplits: 1).last else {
            throw HLSPlaylistError.invalidByteRange(line)
        }
        return try parseByteRangeValue(String(value))
    }

    private func parseByteRangeValue(_ value: String) throws -> PendingByteRange {
        let parts = value.split(separator: "@", maxSplits: 1)
        guard let length = Int64(parts[0]), length > 0 else {
            throw HLSPlaylistError.invalidByteRange(value)
        }
        let offset = parts.count > 1 ? Int64(parts[1]) : nil
        if parts.count > 1, offset == nil {
            throw HLSPlaylistError.invalidByteRange(value)
        }
        return PendingByteRange(length: length, offset: offset)
    }

    private func parseInitializationSegment(
        _ line: String,
        sourceURL: URL,
        encryption: HLSEncryption?,
        nextByteRangeOffsetByURL: inout [String: Int64]
    ) throws -> HLSInitializationSegment {
        let attributes = parseAttributes(from: line)
        guard let uri = attributes["URI"], !uri.isEmpty else {
            throw HLSPlaylistError.invalidPlaylist
        }

        let url = resolve(uri, relativeTo: sourceURL)
        let pendingByteRange = try attributes["BYTERANGE"].map(parseByteRangeValue)
        let byteRange = resolvedByteRange(
            pendingByteRange,
            url: url,
            nextByteRangeOffsetByURL: &nextByteRangeOffsetByURL
        )
        return HLSInitializationSegment(
            url: url,
            encryption: encryption,
            byteRange: byteRange
        )
    }

    private func resolvedByteRange(
        _ pendingByteRange: PendingByteRange?,
        url: URL,
        nextByteRangeOffsetByURL: inout [String: Int64]
    ) -> HLSByteRange? {
        guard let pendingByteRange else {
            return nil
        }
        let key = url.absoluteString
        let offset = pendingByteRange.offset ?? nextByteRangeOffsetByURL[key, default: 0]
        nextByteRangeOffsetByURL[key] = offset + pendingByteRange.length
        return HLSByteRange(length: pendingByteRange.length, offset: offset)
    }

    private func parseAttributes(from line: String) -> [String: String] {
        guard let attributesPart = line.split(separator: ":", maxSplits: 1).last else {
            return [:]
        }

        var attributes: [String: String] = [:]
        var key = ""
        var value = ""
        var readingKey = true
        var isQuoted = false

        func commit() {
            guard !key.isEmpty else { return }
            attributes[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            key = ""
            value = ""
            readingKey = true
        }

        for character in attributesPart {
            if readingKey {
                if character == "=" {
                    readingKey = false
                } else {
                    key.append(character)
                }
            } else {
                if character == "\"" {
                    isQuoted.toggle()
                    value.append(character)
                } else if character == "," && !isQuoted {
                    commit()
                } else {
                    value.append(character)
                }
            }
        }
        commit()
        return attributes
    }

    private func resolve(_ string: String, relativeTo baseURL: URL) -> URL {
        if let absolute = URL(string: string), absolute.scheme != nil {
            return absolute
        }
        return URL(string: string, relativeTo: baseURL)?.absoluteURL ?? baseURL
    }

    static func hexData(_ value: String) -> Data? {
        var hex = value
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") {
            hex.removeFirst(2)
        }
        guard hex.count.isMultiple(of: 2) else {
            return nil
        }

        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}

private struct PendingByteRange {
    var length: Int64
    var offset: Int64?
}
