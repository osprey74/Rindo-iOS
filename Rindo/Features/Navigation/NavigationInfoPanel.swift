import SwiftUI

struct NavigationInfoPanel: View {
    let speedKmh: Double
    let distanceM: Double
    let elapsed: TimeInterval
    let isOffRoute: Bool

    var body: some View {
        HStack(spacing: 0) {
            statCell(
                value: String(format: "%.0f", speedKmh),
                unit: "km/h",
                icon: "speedometer"
            )
            Divider().frame(height: 32)
            statCell(
                value: formatDistance(distanceM),
                unit: distanceM >= 1000 ? "km" : "m",
                icon: "arrow.left.and.right"
            )
            Divider().frame(height: 32)
            statCell(
                value: formatTime(elapsed),
                unit: "",
                icon: "clock"
            )
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if isOffRoute {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.red, lineWidth: 2)
            }
        }
    }

    private func statCell(value: String, unit: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().bold())
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f", meters / 1000)
        }
        return String(format: "%.0f", meters)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        let s = Int(interval) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
