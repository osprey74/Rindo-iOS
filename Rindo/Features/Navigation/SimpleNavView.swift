import SwiftUI

/// 簡易ナビゲーション — OLED 黒背景 + 大矢印 + 距離のみ
struct SimpleNavView: View {
    let maneuver: NavigationManeuver?
    let distanceToNextM: Double
    let remainingDistanceKm: Double
    let speedKmh: Double
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            // OLED 黒背景
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                if let m = maneuver {
                    // マニューバアイコン（大）
                    Image(systemName: ManeuverParser.iconName(for: m.type))
                        .font(.system(size: 120, weight: .bold))
                        .foregroundStyle(.white)

                    // 次の分岐までの距離
                    Text(formatDistance(distanceToNextM))
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)

                    // 指示文
                    Text(m.instruction)
                        .font(.title3)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundStyle(.gray)
                    Text("直進")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)
                }

                Spacer()

                // 下部情報バー
                HStack {
                    VStack(spacing: 4) {
                        Text(String(format: "%.0f", speedKmh))
                            .font(.title.bold().monospacedDigit())
                        Text("km/h")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)

                    Spacer()

                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", remainingDistanceKm))
                            .font(.title.bold().monospacedDigit())
                        Text("km 残り")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)

                    Spacer()

                    // 地図に戻るボタン
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.gray.opacity(0.3), in: Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
