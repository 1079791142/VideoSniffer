import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.downloadRuntimeMode) private var runtimeMode
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \DownloadJob.createdAt, order: .reverse) private var jobs: [DownloadJob]
    @State private var engine: DownloadEngine?
    @State private var selectedCategory: DownloadCategory = .all
    @State private var selectedJob: DownloadJob?
    @State private var isAddingDownload = false
#if !os(macOS)
    @State private var isShowingSettings = false
#endif

    var body: some View {
        Group {
#if os(iOS)
            TabView {
                Tab(.browser, systemImage: "safari") {
                    BrowserView(engine: engine)
                }
                .accessibilityIdentifier("browserTab")

                Tab(.downloads, systemImage: "arrow.down.circle") {
                    DownloadNavigationView(
                        jobs: jobs,
                        selectedCategory: $selectedCategory,
                        selectedJob: $selectedJob,
                        engine: engine,
                        isAddingDownload: $isAddingDownload,
                        isShowingSettings: isShowingSettingsBinding
                    )
                }
                .accessibilityIdentifier("downloadsTab")
            }
#else
            DownloadNavigationView(
                jobs: jobs,
                selectedCategory: $selectedCategory,
                selectedJob: $selectedJob,
                engine: engine,
                isAddingDownload: $isAddingDownload,
                isShowingSettings: isShowingSettingsBinding
            )
#endif
        }
        .task {
            if engine == nil {
                engine = DownloadEngine(modelContext: modelContext, settings: settings, mode: runtimeMode)
            }
        }
        .sheet(isPresented: $isAddingDownload) {
            if let engine {
                AddDownloadView(engine: engine)
            }
        }
#if !os(macOS)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(engine: engine)
                .environment(settings)
        }
#endif
    }

    private var isShowingSettingsBinding: Binding<Bool> {
#if os(macOS)
        .constant(false)
#else
        $isShowingSettings
#endif
    }
}

private struct DownloadNavigationView: View {
    let jobs: [DownloadJob]
    @Binding var selectedCategory: DownloadCategory
    @Binding var selectedJob: DownloadJob?
    let engine: DownloadEngine?
    @Binding var isAddingDownload: Bool
    @Binding var isShowingSettings: Bool

    var body: some View {
        NavigationSplitView {
            DownloadSidebarView(
                jobs: jobs,
                selectedCategory: $selectedCategory,
                isShowingSettings: $isShowingSettings
            )
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 150, ideal: 200)
#else
            .navigationDestination(for: DownloadCategory.self) { category in
                DownloadListView(
                    jobs: jobs.filter { category.contains($0) },
                    category: category,
                    selectedJob: $selectedJob,
                    engine: engine,
                    isAddingDownload: $isAddingDownload
                )
                .onAppear {
                    selectedCategory = category
                }
            }
#endif
        } content: {
            DownloadListView(
                jobs: filteredJobs,
                category: selectedCategory,
                selectedJob: $selectedJob,
                engine: engine,
                isAddingDownload: $isAddingDownload
            )
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 300)
#endif
        } detail: {
            if let selectedJob {
                DownloadDetailView(job: selectedJob, engine: engine)
            } else {
                ContentUnavailableView(
                    .noDownloadSelected,
                    systemImage: "arrow.down.circle",
                    description: Text(.selectATaskOrAddANewM3U8Download)
                )
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            clearSelectionIfNeeded()
        }
        .onChange(of: jobs.map(\.id)) { _, _ in
            clearSelectionIfNeeded()
        }
        .onChange(of: jobs.map(\.statusRawValue)) { _, _ in
            clearSelectionIfNeeded()
        }
    }

    private var filteredJobs: [DownloadJob] {
        jobs.filter { selectedCategory.contains($0) }
    }

    private func clearSelectionIfNeeded() {
        if let selectedJob, !filteredJobs.contains(selectedJob) {
            self.selectedJob = nil
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSamples.modelContainer())
        .environment(PreviewSamples.settings)
}
