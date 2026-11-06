import SwiftData
import SwiftUI

struct StorageInfoView: View {
    let jobs: [DownloadJob]
    let engine: DownloadEngine?
    @State private var sort = StorageSort.newestFirst
    @State private var deletionRequest: DownloadDeletionRequest?
    @State private var isConfirmingDeleteAll = false
    private let usageCalculator = StorageUsageCalculator()

    var body: some View {
        Section {
            if jobs.isEmpty {
                ContentUnavailableView(.noDownloads, systemImage: "externaldrive", description: Text(.storageListEmptyMessage))
            } else {
                Picker(.sortBy, selection: $sort) {
                    ForEach(StorageSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(sortedUsage) { usage in
                    DownloadStorageRowView(usage: usage)
                        .contextMenu {
                            Button(.delete, systemImage: "trash", role: .destructive) {
                                delete(usage.job)
                            }
                        }
                }
                .onDelete { offsets in
                    for index in offsets {
                        deleteImmediately(sortedUsage[index].job)
                    }
                }

                Button(.deleteAllTasks, role: .destructive) {
                    isConfirmingDeleteAll = true
                }
                .disabled(engine == nil)
            }
        } header: {
#if os(macOS)
            EmptyView()
#else
            Text(.storage)
#endif
        } footer: {
            if !jobs.isEmpty {
                Text(.storageSpaceDescription)
            }
        }
        .downloadDeletionHandler(request: $deletionRequest, engine: engine)
        .confirmationDialog(
            String(localized: .deleteAllTasks),
            isPresented: $isConfirmingDeleteAll,
            titleVisibility: .visible
        ) {
#if os(macOS)
            Button(.deleteRecordOnly, role: .destructive) {
                deleteAll(mode: .recordOnly)
            }
            Button(.deleteRecordAndFile, role: .destructive) {
                deleteAll(mode: .recordAndFile)
            }
#else
            Button(.delete, role: .destructive) {
                deleteAll(mode: .recordAndFile)
            }
#endif
            Button(.cancel, role: .cancel) { }
        } message: {
#if os(macOS)
            Text(.deleteAllTasksMacMessage)
#else
            Text(.deleteAllTasksMessage)
#endif
        }
    }

    private var sortedUsage: [StorageUsage] {
        StorageUsageSorter.sorted(jobs.map { usageCalculator.usage(for: $0) }, by: sort)
    }

    private func delete(_ job: DownloadJob) {
        deletionRequest = DownloadDeletionRequest(job: job) { }
    }

    private func deleteImmediately(_ job: DownloadJob) {
        engine?.delete(job, mode: .recordAndFile)
    }

    private func deleteAll(mode: DownloadDeletionMode) {
        engine?.delete(jobs, mode: mode)
    }
}

private extension StorageSort {
    var title: LocalizedStringResource {
        switch self {
        case .newestFirst: .newestFirst
        case .largestFirst: .largestFirst
        }
    }
}

private struct DownloadStorageRowView: View {
    let usage: StorageUsage

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(usage.job.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Text(usage.job.status.title)
                        .foregroundStyle(usage.job.status.statusColor)
                    Text(usage.job.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer()
            Text(usage.byteCount, format: .byteCount(style: .file))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let jobs = [
        PreviewSamples.downloadingJob,
        PreviewSamples.completedJob,
        PreviewSamples.failedJob
    ]

    Form {
        StorageInfoView(jobs: jobs, engine: nil)
    }
    .modelContainer(PreviewSamples.modelContainer())
}
