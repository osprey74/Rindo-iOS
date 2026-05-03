import SwiftUI

/// 詳細ナビゲーション UI — マニューバアイコン + 指示 + 次分岐距離 + 残り
struct TurnByTurnPanel: View {
    let maneuver: NavigationManeuver?
    let distanceToNextM: Double
    let remainingDistanceKm: Double
    let remainingTimeSeconds: Double
    let isRerouting: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isRerouting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("ルートを再検索中...")
                        .font(.subheadline)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            } else if let m = maneuver {
                // 次の分岐案内
                HStack(spacing: 16) {
                    // マニューバアイコン
                    Image(systemName: ManeuverParser.iconName(for: m.type))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        // 距離
                        Text(formatDistance(distanceToNextM))
                            .font(.title.bold().monospacedDigit())

                        // 指示文
                        Text(m.instruction)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .padding(12)
                .background(.ultraThinMaterial)

                // 残り情報
                HStack {
                    Label(String(format: "%.1f km", remainingDistanceKm), systemImage: "arrow.left.and.right")
                    Spacer()
                    Label(formatTime(remainingTimeSeconds), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial.opacity(0.8))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        if m >= 60 {
            return String(format: "%dh %dmin", m / 60, m % 60)
        }
        return "\(m)min"
    }
}
