#if os(iOS)
import SwiftUI

/// The Browse tab: address bar, web view, and a button into the sniffed media
/// list. The view model owns the `WKWebView`, so it is created once and kept
/// for the lifetime of the tab.
struct BrowserView: View {
    let engine: DownloadEngine?

    @State private var model = BrowserViewModel()
    @State private var isShowingSniffedMedia = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrowserURLBarView(model: model)
                BrowserWebView(webView: model.webView)
            }
            .navigationTitle(.browser)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(.sniffedVideos, systemImage: "binoculars") {
                        isShowingSniffedMedia = true
                    }
                    .accessibilityIdentifier("sniffedMediaButton")
                }
            }
            .sheet(isPresented: $isShowingSniffedMedia) {
                BrowserSniffedMediaView(media: model.sniffedMedia, engine: engine)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

#Preview {
    BrowserView(engine: nil)
}
#endif
