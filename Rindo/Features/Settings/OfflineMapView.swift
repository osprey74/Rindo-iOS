import CoreLocation
import SwiftUI

/// オフラインマップのダウンロード・管理画面
struct OfflineMapView: View {
    @Bindable var manager: OfflineMapManager
    var homeCoordinate: CLLocationCoordinate2D?

    private let sapporoCenter = CLLocationCoordinate2D(latitude: 43.06, longitude: 141.35)

    var body: some View {
        List {
            // ストレージ使用量
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("使用容量")
                        Spacer()
                        Text(String(format: "%.0f MB / %.0f MB", manager.totalStorageMB, OfflineMapManager.storageLimitMB))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: manager.totalStorageMB, total: OfflineMapManager.storageLimitMB)
                        .tint(manager.totalStorageMB > OfflineMapManager.storageLimitMB * 0.9 ? .red : .blue)
                }
            } header: {
                Text("ストレージ")
            }

            // ダウンロード
            Section {
                Button {
                    manager.downloadRegion(name: "札幌中心30km", center: sapporoCenter, radiusKm: 30)
                } label: {
                    Label("札幌中心30km", systemImage: "building.2")
                }
                .disabled(manager.isDownloading)

                Button {
                    if let home = homeCoordinate {
                        manager.downloadRegion(name: "自宅から30km", center: home, radiusKm: 30)
                    }
                } label: {
                    Label("自宅から30km", systemImage: "house")
                }
                .disabled(homeCoordinate == nil || manager.isDownloading)

                if manager.isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ダウンロード中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(manager.downloadProgress))
                            .progressViewStyle(.linear)
                    }
                }

                if let error = manager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("ダウンロード")
            } footer: {
                Text("Zoom 8〜15 のタイルを保存します。オフライン時にルーティング（Valhalla）は利用できません")
            }

            // 保存済みパック
            if !manager.packs.isEmpty {
                Section {
                    ForEach(manager.packs) { pack in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(pack.name)
                                Text(pack.isComplete ? "完了" : "ダウンロード中")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f MB", Double(pack.sizeBytes) / 1_048_576))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            manager.deletePack(id: manager.packs[i].id)
                        }
                    }
                } header: {
                    Text("保存済み")
                }
            }
        }
        .navigationTitle("オフラインマップ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
