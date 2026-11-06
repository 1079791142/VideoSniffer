import SwiftUI

struct StatusBadgeView: View {
    let status: DownloadStatus

    var body: some View {
        Text(status.title)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(status.statusColor.opacity(0.18))
            .foregroundStyle(status.statusColor)
            .clipShape(.capsule)
    }
}

#Preview {
    VStack {
        ForEach(DownloadStatus.allCases) { status in
            StatusBadgeView(status: status)
        }
    }
    .padding()
}
