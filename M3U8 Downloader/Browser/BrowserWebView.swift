#if os(iOS)
import SwiftUI
import WebKit

/// Thin `UIViewRepresentable` wrapper around the `WKWebView` owned by the view
/// model. No behavior lives here; navigation is driven by `BrowserURLBarView`.
struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
