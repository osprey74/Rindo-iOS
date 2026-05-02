import SwiftUI

struct MapScreen: View {
    @State private var cyclingRoadsData: Data?
    @State private var osmCyclewaysData: Data?
    @State private var bicycleRoutesData: Data?
    @State private var showAttribution = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RindoMapView(
                cyclingRoadsData: cyclingRoadsData,
                osmCyclewaysData: osmCyclewaysData,
                bicycleRoutesData: bicycleRoutesData
            )
            .ignoresSafeArea()

            // 出典ボタン
            Button {
                showAttribution = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.trailing)
            .padding(.bottom, 56)
        }
        .sheet(isPresented: $showAttribution) {
            AttributionView()
        }
        .overlay(alignment: .top) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 60)
            }
        }
        .task {
            await loadAllLayers()
        }
    }

    private func loadAllLayers() async {
        // Layer 1 & 2: バンドル済み GeoJSON
        loadBundledLayers()
        // Layer 3: API から取得
        await loadCyclingRoads()
    }

    private func loadBundledLayers() {
        if let url = Bundle.main.url(forResource: "sapporo-osm-cycleways", withExtension: "geojson"),
           let data = try? Data(contentsOf: url) {
            osmCyclewaysData = data
        }
        if let url = Bundle.main.url(forResource: "dosou-osm-bicycle-routes", withExtension: "geojson"),
           let data = try? Data(contentsOf: url) {
            bicycleRoutesData = data
        }
    }

    private func loadCyclingRoads() async {
        do {
            cyclingRoadsData = try await APIClient.shared.fetchData(path: "/api/cycling-roads")
            errorMessage = nil
        } catch {
            errorMessage = "サイクリングロードの取得に失敗: \(error.localizedDescription)"
        }
    }
}
