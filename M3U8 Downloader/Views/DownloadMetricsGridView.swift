import SwiftData
import SwiftUI

struct DownloadMetricsGridView: View {
    let job: DownloadJob
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        LazyVGrid(columns: columns) {
            DownloadMetricCardView(
                title: .segments,
                value: segmentProgress,
                systemImage: "rectangle.stack.fill",
                tint: job.status.statusColor
            )

            DownloadMetricCardView(
                title: .downloaded,
                value: job.downloadedBytes.formatted(.byteCount(style: .file)),
                systemImage: "arrow.down.circle.fill",
                tint: job.status.statusColor
            )

            if let resolution = job.selectedVariantResolution,
               !resolution.isEmpty {
                DownloadMetricCardView(
                    title: .resolution,
                    value: resolution,
                    systemImage: "play.rectangle.fill",
                    tint: job.status.statusColor
                )
            }

            if let bandwidth = job.selectedVariantBandwidth,
               bandwidth > 0 {
                DownloadMetricCardView(
                    title: .bitrate,
                    value: bandwidth.formatted(.bitrate),
                    systemImage: "speedometer",
                    tint: job.status.statusColor
                )
            }

        }
        .modifier(DownloadMetricsGlassContainerModifier())
    }

    private var segmentProgress: String {
        guard job.segmentCount > 0 else {
            return "—"
        }

        if job.status == .completed {
            return job.segmentCount.formatted()
        } else {
            return "\(job.completedSegmentCount.formatted()) / \(job.segmentCount.formatted())"
        }
    }

    private var columns: [GridItem] {
        let columnCount = horizontalSizeClass == .compact ? 2 : 4
        return Array(repeating: GridItem(.flexible()), count: columnCount)
    }
}

struct DownloadMetricsGlassContainerModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}

#Preview {
    DownloadMetricsGridView(job: PreviewSamples.downloadingJob)
        .padding()
        .frame(width: 700, height: 300)
        .modelContainer(PreviewSamples.modelContainer())
}
