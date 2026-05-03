import SwiftUI

struct SavedLocationsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var locations: [SavedLocation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// 選択された地点を親に通知（地図でフォーカス）
    var onSelect: ((SavedLocation) -> Void)?

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
                        Button("再試行") { Task { await loadLocations() } }
                    }
                } else if locations.isEmpty {
                    ContentUnavailableView(
                        "地点がありません",
                        systemImage: "mappin",
                        description: Text("Web 版で地点を登録してください")
                    )
                } else {
                    locationList
                }
            }
            .navigationTitle("保存地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task { await loadLocations() }
    }

    private var locationList: some View {
        List {
            ForEach(LocationCategory.allCases, id: \.self) { category in
                let filtered = locations.filter { $0.category == category }
                if !filtered.isEmpty {
                    Section(category.displayName) {
                        ForEach(filtered) { location in
                            Button {
                                onSelect?(location)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(category.emoji)
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(location.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if let notes = location.notes, !notes.isEmpty {
                                            Text(notes)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadLocations() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await APIClient.shared.fetch(
                LocationsResponse.self,
                path: "/api/locations"
            )
            locations = response.locations
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
