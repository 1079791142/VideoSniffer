#if os(iOS)
import Foundation
import Observation
import WebKit

/// Owns the browsing `WKWebView`, its navigation state, and the media
/// candidates reported by `SniffingScript`.
///
/// `WKWebView` exposes progress and title through KVO only; instead of a KVO
/// wrapper this type refreshes its state in the navigation delegate callbacks
/// and, while a page loads, on a short polling loop.
@MainActor
@Observable
final class BrowserViewModel: NSObject {
    let webView: WKWebView

    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var currentURL: URL?
    private(set) var pageTitle = ""
    /// Newest first, one entry per URL.
    private(set) var sniffedMedia: [SniffedMedia] = []

    private let sniffMessageHandler: SniffMessageHandler

    @ObservationIgnored private var progressTask: Task<Void, Never>?

    override init() {
        let configuration = Self.makeConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let handler = SniffMessageHandler()

        self.webView = webView
        self.sniffMessageHandler = handler
        super.init()

        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        configuration.userContentController.add(handler, name: SniffMessageHandler.handlerName)
        handler.onMedia = { [weak self] media in
            self?.record(media)
        }
    }

    // MARK: - Loading

    /// Loads user input, completing a missing scheme with `https`.
    /// Returns `false` when the input cannot be turned into an http(s) URL.
    @discardableResult
    func load(_ input: String) -> Bool {
        guard let url = Self.resolvedURL(from: input) else { return false }
        load(url)
        return true
    }

    func load(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return
        }
        currentURL = url
        pageTitle = ""
        webView.load(URLRequest(url: url))
        startProgressUpdates()
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
        startProgressUpdates()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
        startProgressUpdates()
    }

    func reload() {
        guard webView.url != nil else { return }
        webView.reload()
        startProgressUpdates()
    }

    func stopLoading() {
        webView.stopLoading()
        refreshNavigationState()
    }

    /// Accepts `example.com/path` as well as fully qualified URLs and rejects
    /// anything that is not `http` or `https`.
    nonisolated static func resolvedURL(from input: String) -> URL? {
        // Bound the input the same way incoming sniffed URLs are bounded.
        let maximumAddressLength = 4096
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumAddressLength else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(),
              !host.isEmpty else {
            return nil
        }
        return url
    }

    // MARK: - Sniffed media

    private func record(_ media: SniffedMedia) {
        guard sniffedMedia.first?.urlString != media.urlString else { return }
        var updated = sniffedMedia.filter { $0.urlString != media.urlString }
        updated.insert(media, at: 0)
        sniffedMedia = updated
    }

    // MARK: - State

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            // A short interval keeps the progress bar smooth without KVO.
            let refreshInterval: Duration = .milliseconds(120)
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshNavigationState()
                guard self.webView.isLoading else { return }
                do {
                    try await Task.sleep(for: refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func refreshNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        pageTitle = webView.title ?? ""
        if let url = webView.url {
            currentURL = url
        }
    }

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: SniffingScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        return configuration
    }
}

extension BrowserViewModel: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        startProgressUpdates()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        refreshNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        refreshNavigationState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        refreshNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        refreshNavigationState()
    }
}
#endif
