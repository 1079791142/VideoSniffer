import SwiftData
import SwiftUI

struct DownloadListView: View {
    let jobs: [DownloadJob]
    let category: DownloadCategory
    @Binding var selectedJob: DownloadJob?
    let engine: DownloadEngine?
    @Binding var isAddingDownload: Bool
    @State private var deletionRequest: DownloadDeletionRequest?

    var body: some View {
        List(selection: $selectedJob) {
            ForEach(jobs) { job in
                DownloadRowView(job: job)
                    .tag(job)
                    .contextMenu {
                        Button(.delete, systemImage: "trash", role: .destructive) {
                            delete(job)
                        }
                    }
            }
            .onDelete { offsets in
                for index in offsets {
                    deleteImmediately(jobs[index])
                }
            }
        }
        .overlay {
            if jobs.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: category.systemImage, description: Text(emptyDescription))
            }
        }
        .navigationTitle(category.title)
        .downloadDeletionHandler(request: $deletionRequest, engine: engine)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(.addDownload, systemImage: "plus") {
                    isAddingDownload = true
                }
            }
        }
    }

    private var emptyTitle: LocalizedStringResource {
        switch category {
        case .all: .noDownloads
        case .active: .noActiveDownloads
        case .terminal: .noCompletedDownloads
        }
    }

    private var emptyDescription: LocalizedStringResource {
        switch category {
        case .all: .addAnM3U8LinkToStartDownloading
        case .active: .queuedDownloadingAndPausedTasksAppearHere
        case .terminal: .completedTasksAppearHere
        }
    }

    private func delete(_ job: DownloadJob) {
        deletionRequest = DownloadDeletionRequest(job: job) {
            clearSelection(for: job)
        }
    }

    private func deleteImmediately(_ job: DownloadJob) {
        clearSelection(for: job)
        engine?.delete(job, mode: .recordAndFile)
    }

    private func clearSelection(for job: DownloadJob) {
        if selectedJob == job {
            selectedJob = nil
        }
    }
}

#Preview {
    @Previewable @State var selectedJob: DownloadJob?
    @Previewable @State var isAddingDownload = false

    NavigationStack {
        DownloadListView(
            jobs: [
                PreviewSamples.downloadingJob,
                PreviewSamples.pausedJob,
                PreviewSamples.failedJob
            ],
            category: .all,
            selectedJob: $selectedJob,
            engine: nil,
            isAddingDownload: $isAddingDownload
        )
    }
    .modelContainer(PreviewSamples.modelContainer())
    .environment(PreviewSamples.settings)
}
