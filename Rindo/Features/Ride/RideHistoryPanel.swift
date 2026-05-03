import SwiftData
import SwiftUI

struct RideHistoryPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RideLog.startedAt, order: .reverse) private var rides: [RideLog]

    var onSelect: ((RideLog) -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView(
                        "走行履歴なし",
                        systemImage: "figure.outdoor.cycle",
                        description: Text("走行を記録するとここに表示されます")
                    )
                } else {
                    rideList
                }
            }
            .navigationTitle("走行履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var rideList: some View {
        List {
            ForEach(rides) { ride in
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        onSelect?(ride)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ride.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            HStack(spacing: 12) {
                                Label(String(format: "%.1f km", ride.distanceKm), systemImage: "arrow.left.and.right")
                                Label(formatDuration(ride.durationMin), systemImage: "clock")
                                if ride.caloriesKcal > 0 {
                                    Label(String(format: "%.0f kcal", ride.caloriesKcal), systemImage: "flame")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                if ride.ascentM > 0 {
                                    Text(String(format: "↑%.0f m", ride.ascentM))
                                }
                                Text(String(format: "avg %.1f km/h", ride.avgSpeedKmh))
                                Text(String(format: "max %.1f km/h", ride.maxSpeedKmh))
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }

                    // GPX エクスポート — ShareLink で直接共有（シートの入れ子問題を回避）
                    if let gpxURL = gpxTempURL(for: ride) {
                        ShareLink(item: gpxURL) {
                            Label("GPX エクスポート", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: deleteRides)
        }
    }

    /// GPX を一時ファイルに書き出して URL を返す
    private func gpxTempURL(for ride: RideLog) -> URL? {
        try? GPXExporter.writeToTempFile(from: ride)
    }

    private func deleteRides(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rides[index])
        }
    }

    private func formatDuration(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }
}
