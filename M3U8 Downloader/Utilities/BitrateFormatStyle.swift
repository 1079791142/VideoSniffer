import Foundation

nonisolated struct BitrateFormatStyle: FormatStyle, Codable, Hashable, Sendable {
    func format(_ value: Int) -> String {
        let magnitude = abs(value)
        let unit: String
        let divisor: Double

        switch magnitude {
        case 1_000_000_000...:
            unit = "Gbps"
            divisor = 1_000_000_000
        case 1_000_000...:
            unit = "Mbps"
            divisor = 1_000_000
        case 1_000...:
            unit = "kbps"
            divisor = 1_000
        default:
            return "\(value.formatted(.number)) bps"
        }

        let scaledValue = Double(value) / divisor
        let formattedValue = scaledValue.formatted(
            .number.precision(.fractionLength(0...1))
        )
        return "\(formattedValue) \(unit)"
    }
}

extension FormatStyle where Self == BitrateFormatStyle {
    static var bitrate: BitrateFormatStyle { BitrateFormatStyle() }
}
