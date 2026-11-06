import SwiftData
import SwiftUI

struct DownloadActionsView: View {
    let job: DownloadJob
    let engine: DownloadEngine?
    @State private var deletionRequest: DownloadDeletionRequest?

    var body: some View {
        Group {
            if job.status == .downloading || job.status == .preparing || job.status == .assembling {
                Button(.pause, systemImage: "pause.fill") {
                    engine?.pause(job)
                }
            } else if job.status == .paused || job.status == .queued {
                Button(.resume, systemImage: "play.fill") {
                    engine?.start(job)
                }
            }

            if job.status == .failed {
                Button(.retry, systemImage: "arrow.clockwise") {
                    engine?.retry(job)
                }
            }

            if !job.status.isTerminal {
                Button(.cancel, systemImage: "xmark") {
                    engine?.cancel(job)
                }
            }

#if os(macOS)
            if job.status == .completed, let finalFilePath = job.finalFilePath {
                ShareLink(item: URL(filePath: finalFilePath)) {
                    Label(.export, systemImage: "square.and.arrow.up")
                }
            }
#endif

            if job.status == .completed {
                Button(.delete, systemImage: "trash", role: .destructive) {
                    deletionRequest = DownloadDeletionRequest(job: job) { }
                }
            }
        }
        .downloadDeletionHandler(request: $deletionRequest, engine: engine)
    }
}

#Preview("Paused") {
    List { }
    .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
            DownloadActionsView(job: PreviewSamples.pausedJob, engine: nil)
                .modelContainer(PreviewSamples.modelContainer())
        }
    }
}

#Preview("Failed") {
    List { }
    .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
            DownloadActionsView(job: PreviewSamples.failedJob, engine: nil)
                .modelContainer(PreviewSamples.modelContainer())
        }
    }
}

#Preview("Completed") {
    List { }
    .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
            DownloadActionsView(job: PreviewSamples.completedJob, engine: nil)
                .modelContainer(PreviewSamples.modelContainer())
        }
    }
}
