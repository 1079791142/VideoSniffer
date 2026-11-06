import SwiftUI

struct DownloadMetricCardView: View {
    let title: LocalizedStringResource
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            
            Spacer(minLength: 16)

            Text(value)
                .font(.title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(DownloadMetricCardStyle(tint: tint))
    }
}

struct DownloadMetricCardStyle: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(tint.opacity(0.12)),
                    in: .rect(cornerRadius: 20)
                )
        } else {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: 20))
        }
    }
}

#Preview {
    DownloadMetricCardView(
        title: .downloaded,
        value: 18_420_736.formatted(.byteCount(style: .file)),
        systemImage: "arrow.down.circle.fill",
        tint: .blue
    )
    .padding()
}
