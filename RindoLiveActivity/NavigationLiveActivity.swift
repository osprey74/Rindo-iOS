import ActivityKit
import SwiftUI
import WidgetKit

struct NavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            // ロック画面・StandBy バナー
            HStack(spacing: 12) {
                Image(systemName: context.state.maneuverIcon)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.instruction)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        Label(formatDistance(context.state.distanceToNextM), systemImage: "arrow.turn.up.right")
                        Label(formatDistance(context.state.remainingDistanceKm * 1000), systemImage: "flag")
                        Label(formatTime(context.state.remainingTimeSeconds), systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()
            }
            .padding()
            .background(.black)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.maneuverIcon)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatDistance(context.state.distanceToNextM) + "先")
                            .font(.headline)
                        Text(context.state.instruction)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDistance(context.state.remainingDistanceKm * 1000))
                            .font(.caption.weight(.semibold))
                        Text(formatTime(context.state.remainingTimeSeconds))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.maneuverIcon)
            } compactTrailing: {
                Text(formatDistance(context.state.distanceToNextM))
                    .font(.caption2)
            } minimal: {
                Image(systemName: context.state.maneuverIcon)
            }
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return "\(Int(meters))m"
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h\(minutes % 60)m"
        }
        return "\(minutes)min"
    }
}
