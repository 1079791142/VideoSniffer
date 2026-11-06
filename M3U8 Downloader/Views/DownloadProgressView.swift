import SwiftData
import SwiftUI

struct DownloadProgressView: View {
    let job: DownloadJob

    var body: some View {
        switch job.status {
        case .preparing, .assembling:
            ProgressView()
                .progressViewStyle(.linear)
        case .queued, .completed, .canceled:
            EmptyView()
        default:
            ProgressView(value: job.progress)
                .tint(job.status == .failed ? .red : .accentColor)
        }
    }
}

#Preview {
    VStack {
        ForEach(DownloadStatus.allCases) { status in
            DownloadProgressView(job: PreviewSamples.job(status: status))
        }
    }
    .padding()
    .modelContainer(PreviewSamples.modelContainer())
    .frame(width: 390)
}
