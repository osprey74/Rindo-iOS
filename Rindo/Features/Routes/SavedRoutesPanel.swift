import SwiftUI

struct SavedRoutesPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var routes: [SavedRoute] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// 選択されたルートを親に通知
    var onSelect: (SavedRoute) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("読み込み中...")
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("エラー", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("再試行") { Task { await loadRoutes() } }
                    }
                } else if routes.isEmpty {
                    ContentUnavailableView(
                        "ルートがありません",
                        systemImage: "map",
                        description: Text("Web 版でルートを作成してください")
                    )
                } else {
                    routeList
                }
            }
            .navigationTitle("保存ルート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task { await loadRoutes() }
    }

    private var routeList: some View {
        List(routes) { route in
            Button {
                onSelect(route)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        if let km = route.distanceKm {
                            Label(String(format: "%.1f km", km), systemImage: "arrow.left.and.right")
                        }
                        if let min = route.durationMin {
                            Label(formatDuration(min), systemImage: "clock")
                        }
                        if let ascent = route.ascentM {
                            Label(String(format: "↑%.0f m", ascent), systemImage: "arrow.up.right")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func loadRoutes() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await APIClient.shared.fetch(RoutesResponse.self, path: "/api/routes")
            routes = response.routes
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func formatDuration(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }
}
