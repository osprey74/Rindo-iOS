import Charts
import SwiftUI

struct ElevationChart: View {
    let profile: ElevationProfile
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー（タップで展開）
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "mountain.2")
                    Text("標高プロファイル")
                        .font(.subheadline.bold())
                    Spacer()
                    summaryText
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(.primary)
            }

            if isExpanded {
                VStack(spacing: 8) {
                    chart
                        .frame(height: 140)
                        .padding(.horizontal, 12)

                    statsRow
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var summaryText: some View {
        HStack(spacing: 8) {
            Text(String(format: "↑%.0fm", profile.totalAscentM))
                .font(.caption)
                .foregroundStyle(.green)
            Text(String(format: "↓%.0fm", profile.totalDescentM))
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(profile.points.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("距離", point.distanceKm),
                    y: .value("標高", point.elevationM)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.green.opacity(0.3), .green.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("距離", point.distanceKm),
                    y: .value("標高", point.elevationM)
                )
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text(String(format: "%.0f", km))
                    }
                }
                AxisGridLine()
            }
        }
        .chartYScale(domain: chartYMin...chartYMax)
    }

    private var statsRow: some View {
        HStack {
            stat(label: "距離", value: String(format: "%.1f km", profile.totalDistanceKm))
            Divider().frame(height: 16)
            stat(label: "最低", value: String(format: "%.0f m", profile.minElevationM))
            Divider().frame(height: 16)
            stat(label: "最高", value: String(format: "%.0f m", profile.maxElevationM))
            Divider().frame(height: 16)
            stat(label: "最大勾配", value: String(format: "%.1f%%", profile.maxSlopePct))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    /// 標高レンジに余白を加える（上下とも 10% + 最低 5m）
    private var chartYMin: Double {
        let range = profile.maxElevationM - profile.minElevationM
        let padding = max(range * 0.1, 5)
        return profile.minElevationM - padding
    }

    private var chartYMax: Double {
        let range = profile.maxElevationM - profile.minElevationM
        let padding = max(range * 0.1, 5)
        return profile.maxElevationM + padding
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).fontWeight(.medium)
            Text(value)
        }
        .frame(maxWidth: .infinity)
    }
}
