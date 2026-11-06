import AVKit
import SwiftUI

struct VideoPlayerView: View {
    let fileURL: URL
    let bookmarkData: Data?

    @State private var player: AVPlayer?
    @State private var aspectRatio = 16.0 / 9.0
#if os(iOS)
    @State private var hlsServer: LocalHLSServer?
#endif
#if os(macOS)
    @State private var accessedSecurityScopedURL: URL?
    @State private var accessedBookmarkData: Data?
#endif

    var body: some View {
        PlayerAspectLayout(aspectRatio: aspectRatio, maximumHeight: 400) {
            if let player {
                SystemVideoPlayer(player: player)
            }
        }
        .task(id: fileURL) {
            await configurePlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
            stopLocalHLSServer()
            stopSecurityScopedAccess()
        }
    }

    private func configurePlayer() async {
        refreshSecurityScopedAccess()

        guard fileExists else {
            player = nil
            stopSecurityScopedAccess()
            return
        }

        guard let playbackURL = await playbackURL() else {
            player = nil
            return
        }

        let asset = AVURLAsset(url: playbackURL)
        player = AVPlayer(url: playbackURL)
        aspectRatio = await videoAspectRatio(for: asset) ?? aspectRatio
    }

    private func playbackURL() async -> URL? {
#if os(iOS)
        guard fileURL.pathExtension.caseInsensitiveCompare("m3u8") == .orderedSame else {
            stopLocalHLSServer()
            return fileURL
        }

        stopLocalHLSServer()

        do {
            let server = try LocalHLSServer(
                rootDirectory: fileURL.deletingLastPathComponent(),
                playlistFileName: fileURL.lastPathComponent
            )
            try await server.start()
            hlsServer = server
            return try server.playlistURL()
        } catch {
            return nil
        }
#else
        return fileURL
#endif
    }

    private var fileExists: Bool {
#if os(macOS)
        withSecurityScopedAccess(bookmarkData: bookmarkData) {
            FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
        }
#else
        FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
#endif
    }

    private func refreshSecurityScopedAccess() {
#if os(macOS)
        guard let bookmarkData else {
            stopSecurityScopedAccess()
            return
        }

        guard accessedBookmarkData != bookmarkData else {
            return
        }

        stopSecurityScopedAccess()

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            return
        }

        accessedSecurityScopedURL = url
        accessedBookmarkData = bookmarkData
#endif
    }

    private func stopSecurityScopedAccess() {
#if os(macOS)
        accessedSecurityScopedURL?.stopAccessingSecurityScopedResource()
        accessedSecurityScopedURL = nil
        accessedBookmarkData = nil
#endif
    }

    private func stopLocalHLSServer() {
#if os(iOS)
        hlsServer?.stop()
        hlsServer = nil
#endif
    }

    private func videoAspectRatio(for asset: AVAsset) async -> Double? {
        do {
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let width = abs(transformedSize.width)
            let height = abs(transformedSize.height)

            guard width > 0, height > 0 else {
                return nil
            }

            return width / height
        } catch {
            return nil
        }
    }
}

#if os(iOS)
private struct SystemVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        playerViewController.showsPlaybackControls = true
        return playerViewController
    }

    func updateUIViewController(_ playerViewController: AVPlayerViewController, context: Context) {
        playerViewController.player = player
    }
}
#elseif os(macOS)
private struct SystemVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        playerView.player = player
    }
}
#endif

private struct PlayerAspectLayout: Layout {
    let aspectRatio: Double
    let maximumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let proposedWidth = proposal.width ?? maximumHeight * aspectRatio
        let width = max(0, proposedWidth)
        let height = min(maximumHeight, width / aspectRatio)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let size = sizeThatFits(proposal: ProposedViewSize(bounds.size), subviews: subviews, cache: &cache)
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(size))
        }
    }
}
