import SwiftUI

struct DownloadDeletionRequest: Identifiable {
    let job: DownloadJob
    let completion: () -> Void

    var id: UUID {
        job.id
    }
}

struct DownloadDeletionHandler: ViewModifier {
    @Binding var request: DownloadDeletionRequest?
    let engine: DownloadEngine?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                String(localized: .deleteDownload),
                isPresented: isPresentingDeletionDialog,
                titleVisibility: .visible,
                presenting: request
            ) { request in
                if allowsRecordOnlyDeletion(for: request.job) {
                    Button(.deleteRecordOnly, role: .destructive) {
                        delete(request, mode: .recordOnly)
                    }
                    Button(.deleteRecordAndFile, role: .destructive) {
                        delete(request, mode: .recordAndFile)
                    }
                } else {
                    Button(.delete, role: .destructive) {
                        delete(request, mode: .recordAndFile)
                    }
                }
                Button(.cancel, role: .cancel) { }
            } message: { request in
                if allowsRecordOnlyDeletion(for: request.job) {
                    Text(.whetherToRemoveDownloadedFile(request.job.title))
                } else if request.job.status == .completed {
                    Text(.deleteCompletedDownloadMessage(request.job.title))
                } else {
                    Text(.deleteDownloadRecordMessage(request.job.title))
                }
            }
    }

    private func allowsRecordOnlyDeletion(for job: DownloadJob) -> Bool {
#if os(macOS)
        job.status == .completed
#else
        false
#endif
    }

    private func delete(_ request: DownloadDeletionRequest, mode: DownloadDeletionMode) {
        request.completion()
        engine?.delete(request.job, mode: mode)
        self.request = nil
    }

    private var isPresentingDeletionDialog: Binding<Bool> {
        Binding {
            request != nil
        } set: { isPresented in
            if !isPresented {
                request = nil
            }
        }
    }
}

extension View {
    func downloadDeletionHandler(
        request: Binding<DownloadDeletionRequest?>,
        engine: DownloadEngine?
    ) -> some View {
        modifier(DownloadDeletionHandler(request: request, engine: engine))
    }
}
