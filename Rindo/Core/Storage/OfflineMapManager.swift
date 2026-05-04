import CoreLocation
import Foundation
import MapLibre

/// MLNOfflineStorage を使ったオフラインタイルダウンロード管理
@Observable
@MainActor
final class OfflineMapManager {
    // MARK: - Public State

    private(set) var packs: [OfflinePack] = []
    private(set) var isDownloading = false
    private(set) var downloadProgress: Float = 0
    private(set) var errorMessage: String?

    var totalStorageMB: Double {
        Double(packs.reduce(0) { $0 + $1.sizeBytes }) / 1_048_576
    }

    static let storageLimitMB: Double = 500

    // MARK: - Types

    struct OfflinePack: Identifiable {
        let id: String
        let name: String
        var sizeBytes: UInt64
        var completedResources: UInt64
        var expectedResources: UInt64
        var isComplete: Bool { expectedResources > 0 && completedResources >= expectedResources }
    }

    // MARK: - Private

    private let styleURL: URL
    private var progressObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?

    init() {
        styleURL = Bundle.main.url(forResource: "osm-style", withExtension: "json")!
        setupNotifications()
        loadExistingPacks()
    }

    // MARK: - Download

    /// 指定座標を中心に radiusKm 圏のタイルをダウンロード
    func downloadRegion(name: String, center: CLLocationCoordinate2D, radiusKm: Double) {
        guard !isDownloading else { return }

        let estimatedMB = estimateSize(radiusKm: radiusKm)
        guard totalStorageMB + estimatedMB <= Self.storageLimitMB else {
            errorMessage = "ストレージ上限（\(Int(Self.storageLimitMB))MB）を超えます"
            return
        }

        let bounds = Self.boundingBox(center: center, radiusKm: radiusKm)
        let region = MLNTilePyramidOfflineRegion(
            styleURL: styleURL,
            bounds: bounds,
            fromZoomLevel: 8,
            toZoomLevel: 15
        )

        guard let context = name.data(using: .utf8) else { return }
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        MLNOfflineStorage.shared.addPack(for: region, withContext: context) { [weak self] pack, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    self?.isDownloading = false
                    return
                }
                pack?.resume()
            }
        }
    }

    /// パック削除
    func deletePack(id: String) {
        guard let mlnPacks = MLNOfflineStorage.shared.packs else { return }
        for mlnPack in mlnPacks {
            let packName = String(data: mlnPack.context, encoding: .utf8) ?? ""
            if packName == id {
                MLNOfflineStorage.shared.removePack(mlnPack) { [weak self] error in
                    Task { @MainActor [weak self] in
                        if error == nil {
                            self?.packs.removeAll { $0.id == id }
                        }
                    }
                }
                break
            }
        }
    }

    // MARK: - Load

    func loadExistingPacks() {
        guard let mlnPacks = MLNOfflineStorage.shared.packs else {
            packs = []
            return
        }
        packs = mlnPacks.map { pack in
            let name = String(data: pack.context, encoding: .utf8) ?? "不明"
            let progress = pack.progress
            return OfflinePack(
                id: name,
                name: name,
                sizeBytes: progress.countOfBytesCompleted,
                completedResources: progress.countOfResourcesCompleted,
                expectedResources: progress.countOfResourcesExpected
            )
        }
    }

    // MARK: - Private

    private func setupNotifications() {
        progressObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.MLNOfflinePackProgressChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleProgressChange(notification)
            }
        }

        errorObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.MLNOfflinePackError,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                if let error = notification.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError {
                    self?.errorMessage = error.localizedDescription
                }
                self?.isDownloading = false
            }
        }
    }

    private func handleProgressChange(_ notification: Notification) {
        guard let pack = notification.object as? MLNOfflinePack else { return }
        let progress = pack.progress

        if progress.countOfResourcesExpected > 0 {
            downloadProgress = Float(progress.countOfResourcesCompleted) / Float(progress.countOfResourcesExpected)
        }

        if progress.countOfResourcesCompleted >= progress.countOfResourcesExpected
            && progress.countOfResourcesExpected > 0
        {
            isDownloading = false
            downloadProgress = 1.0
        }

        loadExistingPacks()
    }

    private func estimateSize(radiusKm: Double) -> Double {
        // ラフな見積もり: zoom 8-15, ラスタータイル (256x256 PNG ~20KB/tile)
        // 面積に比例、30km 圏 ≈ 100MB
        return (radiusKm / 30.0) * (radiusKm / 30.0) * 100
    }

    private static func boundingBox(center: CLLocationCoordinate2D, radiusKm: Double) -> MLNCoordinateBounds {
        let latDelta = radiusKm / 111.0
        let lonDelta = radiusKm / (111.0 * cos(center.latitude * .pi / 180))
        return MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: center.latitude - latDelta, longitude: center.longitude - lonDelta),
            ne: CLLocationCoordinate2D(latitude: center.latitude + latDelta, longitude: center.longitude + lonDelta)
        )
    }
}
