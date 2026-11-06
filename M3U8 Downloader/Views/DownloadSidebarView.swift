import SwiftUI

struct DownloadSidebarView: View {
    let jobs: [DownloadJob]
    @Binding var selectedCategory: DownloadCategory
    @Binding var isShowingSettings: Bool

    var body: some View {
        Group {
#if os(macOS)
            List(DownloadCategory.allCases, selection: $selectedCategory) { category in
                CategoryRowView(category: category, count: count(for: category))
                    .tag(category)
            }
#else
            List(DownloadCategory.allCases) { category in
                NavigationLink(value: category) {
                    CategoryRowView(category: category, count: count(for: category))
                }
            }
#endif
        }
        .navigationTitle(.downloads)
#if !os(macOS)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(.settings, systemImage: "gear") {
                    isShowingSettings = true
                }
            }
        }
#endif
    }

    private func count(for category: DownloadCategory) -> Int {
        jobs.filter { category.contains($0) }.count
    }
}

private struct CategoryRowView: View {
    let category: DownloadCategory
    let count: Int

    var body: some View {
        Label {
            HStack {
                Text(category.title)
                Spacer()
                Text(count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: category.systemImage)
        }
    }
}

#Preview {
    @Previewable @State var selectedCategory: DownloadCategory = .all
    @Previewable @State var isShowingSettings = false

    NavigationStack {
        DownloadSidebarView(
            jobs: [
                PreviewSamples.downloadingJob,
                PreviewSamples.completedJob,
                PreviewSamples.failedJob
            ],
            selectedCategory: $selectedCategory,
            isShowingSettings: $isShowingSettings
        )
    }
}
