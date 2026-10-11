import SwiftUI

/// 簡易ナビゲーション — OLED 黒背景 + 大矢印 + 距離のみ
struct SimpleNavView: View {
    let maneuver: NavigationManeuver?
    let distanceToNextM: Double
    let remainingDistanceKm: Double
    let speedKmh: Double
    var onDismiss: () -> Void

    // 折りたたみ端末の半開き時の折り目（なければ nil）
    @State private var fold: CGRect?

    var body: some View {
        ZStack {
            // OLED 黒背景
            Color.black.ignoresSafeArea()

            if let fold, FoldLayout.isVertical(fold) {
                // 縦の折り目: 左に案内、右に走行情報（折り目の上に大きな表示を置かない）
                HStack(spacing: 0) {
                    maneuverSection
                        .frame(width: fold.minX)
                    Color.clear
                        .frame(width: fold.width)
                    infoBar
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            } else if let fold {
                // 横の折り目: 上に案内、下に走行情報
                VStack(spacing: 0) {
                    maneuverSection
                        .frame(height: fold.minY)
                    Color.clear
                        .frame(height: fold.height)
                    infoBar
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                VStack(spacing: 32) {
                    Spacer()
                    maneuverSection
                    Spacer()
                    infoBar
                }
            }
        }
        .onGeometryChange(for: CGRect?.self) { FoldLayout.activeFold(in: $0) } action: { fold = $0 }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }

    /// マニューバアイコン・次の分岐までの距離・指示文
    private var maneuverSection: some View {
        VStack(spacing: 32) {
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
        }
    }

    /// 下部情報バー
    private var infoBar: some View {
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

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
