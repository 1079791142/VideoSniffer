import Foundation
import WebKit

/// Receives media candidates reported by `SniffingScript`.
///
/// Messages come from web content and are treated as untrusted data: fields
/// are validated and bounded, and nothing is ever evaluated or executed.
/// The handler does not retain the browser view model; the view model assigns
/// `onMedia` with a weak capture, so the `WKUserContentController` that owns
/// this handler cannot keep the view model alive.
final class SniffMessageHandler: NSObject, WKScriptMessageHandler {
    /// Must match the handler name used by `SniffingScript`.
    static let handlerName = "videoSniffer"

    private static let maximumURLStringLength = 4096

    /// Called on the main actor for every validated candidate.
    var onMedia: ((SniffedMedia) -> Void)?

    override init() {
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName,
              let body = message.body as? [String: Any] else {
            return
        }

        guard let rawURL = body["url"] as? String,
              let url = Self.validatedURL(from: rawURL) else {
            return
        }

        let pageURLString = (body["pageURL"] as? String).flatMap { pageURLString in
            guard let pageURL = Self.validatedURL(from: pageURLString) else {
                return nil
            }
            return pageURL.absoluteString
        }

        let media = SniffedMedia(
            urlString: url.absoluteString,
            kind: SniffedMediaKind(reportedValue: body["kind"] as? String, url: url),
            pageURLString: pageURLString,
            discoveredAt: .now
        )
        onMedia?(media)
    }

    /// The validation boundary for every URL that comes out of a page.
    ///
    /// Accepts only absolute `http`/`https` URLs with a host and bounded
    /// length; everything else (including `blob:`, `data:`, and custom
    /// schemes) is dropped. Not isolated so unit tests can exercise it.
    nonisolated static func validatedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maximumURLStringLength,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil else {
            return nil
        }
        return url
    }
}
