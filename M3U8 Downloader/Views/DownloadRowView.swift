import SwiftData
import SwiftUI

struct DownloadRowView: View {
    let job: DownloadJob

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading) {
                    Text(job.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(job.sourceURLString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadgeView(status: job.status)
            }

            DownloadProgressView(job: job)

            if job.status != .queued && job.status != .preparing {
                HStack {
                    Text(.segments(job.completedSegmentCount, job.segmentCount))
                        .monospacedDigit()
                    Spacer()
                    Text(job.downloadedBytes.formatted(.byteCount(style: .file)))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack {
        ForEach(DownloadStatus.allCases) { status in
            DownloadRowView(job: PreviewSamples.job(status: status))
                .padding()
                .background(.background)
        }
    }
    .modelContainer(PreviewSamples.modelContainer())
    .frame(width: 390)
}
