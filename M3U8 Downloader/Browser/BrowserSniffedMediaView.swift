#if os(iOS)
import SwiftUI

/// List of media candidates found in the current browsing session.
/// The candidates are page-reported data, so only their URL is used, and
/// downloading is offered solely for HLS playlists the engine can parse.
struct BrowserSniffedMediaView: View {
    let media: [SniffedMedia]
    let engine: DownloadEngine?

    @State private var addedURLStrings: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if media.contains(where: { $0.kind == .hls }) {
                Section {
                    ForEach(media.filter { $0.kind == .hls }) { item in
                        BrowserSniffedMediaRow(
                            media: item,
                            isAdded: addedURLStrings.contains(item.urlString),
                            engine: engine,
                            addDownload: addDownload
                        )
                    }
                } header: {
                    Text(.hlsPlaylist)
                }
            }

            if media.contains(where: { $0.kind == .file }) {
                Section {
                    ForEach(media.filter { $0.kind == .file }) { item in
                        BrowserSniffedMediaRow(
                            media: item,
                            isAdded: addedURLStrings.contains(item.urlString),
                            engine: engine,
                            addDownload: addDownload
                        )
                    }
                } header: {
                    Text(.videoFile)
                } footer: {
                    Text(.directVideoFileDownloadIsNotSupportedYet)
                }
            }
        }
        .overlay {
            if media.isEmpty {
                ContentUnavailableView(.noVideosFound, systemImage: "video.slash")
            }
        }
        .alert(
            String(localized: .unableToAddDownload),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(.ok, role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? String(localized: .unknownError))
        }
    }

    private func addDownload(for item: SniffedMedia) {
        guard let engine, item.kind == .hls else { return }
        do {
            let outputName = AddDownloadDestination(
                urlString: item.urlString,
                outputName: "",
                authorizedURL: nil
            ).resolvedName
            try engine.addJob(sourceURLString: item.urlString, outputName: outputName, destinationURL: nil)
            addedURLStrings.insert(item.urlString)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BrowserSniffedMediaRow: View {
    let media: SniffedMedia
    let isAdded: Bool
    let engine: DownloadEngine?
    let addDownload: (SniffedMedia) -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(media.urlString)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(media.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isAdded {
                Label(.added, systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(Text(.added))
            } else {
                Button(.download, systemImage: "arrow.down.circle") {
                    addDownload(media)
                }
                .labelStyle(.iconOnly)
                .disabled(engine == nil || media.kind != .hls)
            }
        }
    }
}

#Preview {
    BrowserSniffedMediaView(
        media: [
            SniffedMedia(
                urlString: "https://example.com/video/index.m3u8",
                kind: .hls,
                pageURLString: "https://example.com",
                discoveredAt: .now
            ),
            SniffedMedia(
                urlString: "https://example.com/video/clip.mp4",
                kind: .file,
                pageURLString: "https://example.com",
                discoveredAt: .now
            )
        ],
        engine: nil
    )
}
#endif
