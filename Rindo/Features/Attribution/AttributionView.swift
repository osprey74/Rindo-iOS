import SwiftUI

struct AttributionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("地図データ") {
                    attribution(
                        title: "OpenStreetMap",
                        detail: "© OpenStreetMap contributors（ODbL）",
                        url: "https://www.openstreetmap.org/copyright"
                    )
                }

                Section("サイクリングロードデータ") {
                    attribution(
                        title: "北海道大規模自転車道",
                        detail: "北海道建設部土木局提供（CC-BY）"
                    )
                    attribution(
                        title: "さっぽろサイクリングマップ",
                        detail: "出典：札幌市建設局（デジタイズデータ）"
                    )
                }

                Section("標高データ") {
                    attribution(
                        title: "SRTM 30m",
                        detail: "NASA Shuttle Radar Topography Mission"
                    )
                    attribution(
                        title: "OpenTopoData",
                        detail: "標高 API サービス",
                        url: "https://www.opentopodata.org"
                    )
                }

                Section("ルーティング") {
                    attribution(
                        title: "Valhalla",
                        detail: "BSD-3-Clause License",
                        url: "https://github.com/valhalla/valhalla"
                    )
                }

                Section("天気予報") {
                    attribution(
                        title: "気象庁",
                        detail: "天気予報 API",
                        url: "https://www.jma.go.jp"
                    )
                }

                Section("地図エンジン") {
                    attribution(
                        title: "MapLibre Native",
                        detail: "BSD-2-Clause License",
                        url: "https://github.com/maplibre/maplibre-native"
                    )
                }
            }
            .navigationTitle("出典・ライセンス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func attribution(title: String, detail: String, url: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if let urlString = url, let link = URL(string: urlString) {
                Link(urlString, destination: link)
                    .font(.caption2)
            }
        }
        .padding(.vertical, 2)
    }
}
