import Foundation
import Testing
@testable import M3U8_Downloader

/// Validation boundaries for values that come out of web content.
struct BrowserSniffingTests {
    @Test func validatedURLAcceptsAbsoluteHTTPAndHTTPS() {
        #expect(SniffMessageHandler.validatedURL(from: "https://example.com/video.m3u8")?.host() == "example.com")
        #expect(SniffMessageHandler.validatedURL(from: "http://example.com")?.scheme == "http")
        #expect(SniffMessageHandler.validatedURL(from: "  https://example.com/a.mp4  ")?.absoluteString == "https://example.com/a.mp4")
    }

    @Test func validatedURLRejectsNonFetchableSchemes() {
        #expect(SniffMessageHandler.validatedURL(from: "blob:https://example.com/1234") == nil)
        #expect(SniffMessageHandler.validatedURL(from: "data:video/mp4;base64,AAAA") == nil)
        #expect(SniffMessageHandler.validatedURL(from: "file:///tmp/a.m3u8") == nil)
        #expect(SniffMessageHandler.validatedURL(from: "javascript:alert(1)") == nil)
    }

    @Test func validatedURLRejectsMalformedInput() {
        #expect(SniffMessageHandler.validatedURL(from: "") == nil)
        #expect(SniffMessageHandler.validatedURL(from: "   ") == nil)
        #expect(SniffMessageHandler.validatedURL(from: "example.com/a.m3u8") == nil)
        #expect(SniffMessageHandler.validatedURL(from: "https://") == nil)
        #expect(SniffMessageHandler.validatedURL(from: "https://" + String(repeating: "a", count: 4096)) == nil)
    }

    @Test func kindIsInferredFromURLWhenReportIsMissingOrUnknown() throws {
        let playlistURL = try #require(URL(string: "https://example.com/video/index.m3u8"))
        #expect(SniffedMediaKind(reportedValue: nil, url: playlistURL) == .hls)
        #expect(SniffedMediaKind(reportedValue: "unknown", url: playlistURL) == .hls)

        let fileURL = try #require(URL(string: "https://example.com/video.mp4"))
        #expect(SniffedMediaKind(reportedValue: nil, url: fileURL) == .file)
        #expect(SniffedMediaKind(reportedValue: "file", url: fileURL) == .file)
        #expect(SniffedMediaKind(reportedValue: "hls", url: fileURL) == .hls)
    }

#if os(iOS)
    @Test func enteredAddressGetsHTTPSWhenSchemeIsMissing() {
        #expect(BrowserViewModel.resolvedURL(from: "example.com")?.absoluteString == "https://example.com")
        #expect(BrowserViewModel.resolvedURL(from: " example.com/a ")?.host() == "example.com")
        #expect(BrowserViewModel.resolvedURL(from: "https://example.com/a")?.scheme == "https")
    }

    @Test func enteredAddressRejectsNonWebSchemes() {
        #expect(BrowserViewModel.resolvedURL(from: "") == nil)
        #expect(BrowserViewModel.resolvedURL(from: "ftp://example.com") == nil)
        #expect(BrowserViewModel.resolvedURL(from: "file:///tmp/a.html") == nil)
        #expect(BrowserViewModel.resolvedURL(from: "blob:https://example.com/1") == nil)
    }
#endif
}
