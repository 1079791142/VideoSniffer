import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DownloadDetailView: View {
    let job: DownloadJob
    let engine: DownloadEngine?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading) {
#if os(macOS)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(job.title)
                                .font(.title2)
                                .bold()
                            Text(job.sourceURLString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        StatusBadgeView(status: job.status)
                    }
#else
                    VStack(alignment: .leading) {
                        Text(job.status.title)
                            .font(.title2)
                            .bold()
                            .foregroundStyle(job.status.statusColor)
                        Text(job.sourceURLString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
#endif
                    DownloadProgressView(job: job)
                    if let errorMessage = job.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .listRowSeparator(.hidden)

            DownloadMetricsGridView(job: job)
#if os(macOS)
                .padding(.top, 12)
                .padding(.bottom, 28)
#endif
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if let downloadedFileURL {
                Section {
                    VideoPlayerView(fileURL: downloadedFileURL, bookmarkData: job.destinationBookmark)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            }

            Section(String(localized: .information)) {
                LabeledContent(String(localized: .outputName), value: job.outputFileName)

#if os(macOS)
                if let finalFilePath = job.finalFilePath {
                    LabeledContent(String(localized: .outputPath)) {
                        HStack {
                            Text(finalFilePath)
                                .textSelection(.enabled)
                            Button(.showInFinder, systemImage: "arrow.up.forward.circle.fill") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: finalFilePath)])
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .controlSize(.small)
                        }
                    }
                    .multilineTextAlignment(.trailing)
                }
#endif

                LabeledContent(
                    String(localized: .createdAt),
                    value: job.createdAt.formatted(date: .abbreviated, time: .standard)
                )

                if let completedAt = job.completedAt {
                    LabeledContent(String(localized: .completedAt), value: completedAt.formatted(date: .abbreviated, time: .standard))
                } else if let startedAt = job.startedAt {
                    LabeledContent(String(localized: .startedAt), value: startedAt.formatted(date: .abbreviated, time: .standard))
                }
            }

            Section(String(localized: .segments)) {
                ForEach(sortedSegments) { segment in
                    HStack {
                        Text("#\(segment.index + 1)")
                            .monospacedDigit()
                        Text(segment.status.title)
                            .foregroundStyle(segment.statusColor)
                        Spacer()
                        Text(segment.byteCount, format: .byteCount(style: .file))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
#if !os(macOS)
        .listStyle(.plain)
#endif
        .navigationTitle(job.title)
        .toolbar {
            ToolbarItemGroup {
                DownloadActionsView(job: job, engine: engine)
            }
        }
    }

    private var sortedSegments: [DownloadSegment] {
        job.segments
            .filter { !$0.isInitializationSegment }
            .sorted { $0.index < $1.index }
    }

    private var downloadedFileURL: URL? {
#if os(iOS)
        let fileStore = DownloadFileStore()
        let storedFileURL = job.finalFilePath.map { URL(filePath: $0) }
        let appStoredFileURL = try? fileStore.finalMediaURL(for: job)

        for fileURL in [storedFileURL, appStoredFileURL].compactMap(\.self) {
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                return fileURL
            }
        }

        return nil
#else
        guard let finalFilePath = job.finalFilePath else {
            return nil
        }

        let fileURL = URL(filePath: finalFilePath)
        return withSecurityScopedAccess(bookmarkData: job.destinationBookmark) {
            FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
        }
#endif
    }
}

#Preview("Downloading") {
    NavigationStack {
        DownloadDetailView(job: PreviewSamples.downloadingJob, engine: nil)
    }
    .modelContainer(PreviewSamples.modelContainer())
    .environment(PreviewSamples.settings)
}

#Preview("Completed") {
    NavigationStack {
        DownloadDetailView(job: PreviewSamples.completedJob, engine: nil)
    }
    .modelContainer(PreviewSamples.modelContainer())
    .environment(PreviewSamples.settings)
}

#Preview("Failed") {
    NavigationStack {
        DownloadDetailView(job: PreviewSamples.failedJob, engine: nil)
    }
    .modelContainer(PreviewSamples.modelContainer())
    .environment(PreviewSamples.settings)
}

#Preview("Large Type") {
    NavigationStack {
        DownloadDetailView(job: PreviewSamples.downloadingJob, engine: nil)
    }
    .modelContainer(PreviewSamples.modelContainer())
    .environment(PreviewSamples.settings)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Compact Width") {
    NavigationStack {
        DownloadDetailView(job: PreviewSamples.downloadingJob, engine: nil)
    }
    .modelContainer(PreviewSamples.modelContainer())
    .environment(PreviewSamples.settings)
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 390, height: 844)
}
