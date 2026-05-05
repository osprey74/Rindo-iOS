import SwiftUI

/// サイクリングロードタップ時に表示する詳細カード
struct CyclingRoadDetailCard: View {
    let road: CyclingRoadFeature
    let elevationProfile: ElevationProfile?
    let isLoadingElevation: Bool
    let onStartNavigation: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(road.properties.name)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(road.properties.ward)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                        Text(road.properties.roadTypeLabel)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                        if road.properties.isLargeScale {
                            Text("大規模自転車道")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(UIColor(red: 0x6A/255, green: 0x5A/255, blue: 0xCD/255, alpha: 1)), in: Capsule())
                        }
                    }
                }
                Spacer()
                Button { withAnimation { onDismiss() } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // 距離情報
            HStack(spacing: 16) {
                statItem(label: "距離", value: formatDistance(road.lengthMeters))
                if let profile = elevationProfile {
                    Divider().frame(height: 20)
                    statItem(label: "獲得標高", value: String(format: "↑%.0f m", profile.totalAscentM))
                    Divider().frame(height: 20)
                    statItem(label: "最高地点", value: String(format: "%.0f m", profile.maxElevationM))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            // 標高プロファイル
            if let profile = elevationProfile {
                ElevationChart(profile: profile)
            } else if isLoadingElevation {
                ProgressView("標高読み込み中...")
                    .padding(8)
                    .frame(maxWidth: .infinity)
            }

            // ナビ開始ボタン
            Button(action: onStartNavigation) {
                Label("ナビ開始", systemImage: "location.north.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).fontWeight(.medium)
            Text(value)
        }
    }
}
