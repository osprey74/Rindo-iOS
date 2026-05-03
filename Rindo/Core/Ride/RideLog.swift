import CoreLocation
import Foundation
import SwiftData

/// 完了した走行ログ（SwiftData 永続化）
@Model
final class RideLog {
    var id: UUID
    var name: String?
    var startedAt: Date
    var endedAt: Date
    var distanceKm: Double
    var durationMin: Double
    var ascentM: Double
    var descentM: Double
    var maxSpeedKmh: Double
    var avgSpeedKmh: Double
    var caloriesKcal: Double
    /// トラック: JSON [[lon, lat, ele, epoch_s, speed_mps], ...]
    var trackJSON: Data
    /// サーバにアップロード済みか
    var uploaded: Bool

    init(summary: RideSummary) {
        self.id = UUID()
        self.startedAt = summary.startedAt
        self.endedAt = summary.endedAt
        self.distanceKm = summary.distanceKm
        self.durationMin = summary.durationMin
        self.ascentM = summary.ascentM
        self.descentM = summary.descentM
        self.maxSpeedKmh = summary.maxSpeedKmh
        self.avgSpeedKmh = summary.avgSpeedKmh
        self.caloriesKcal = summary.caloriesKcal
        self.uploaded = false

        // トラックポイントを JSON エンコード
        let track: [[Double]] = summary.trackPoints.map { pt in
            [
                pt.coordinate.longitude,
                pt.coordinate.latitude,
                pt.altitude,
                pt.timestamp.timeIntervalSince1970,
                pt.speed,
            ]
        }
        self.trackJSON = (try? JSONEncoder().encode(track)) ?? Data()
    }

    /// 走行名（日付ベースのデフォルト）
    var displayName: String {
        name ?? "走行ログ \(startedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    /// 座標配列を復元
    var coordinates: [CLLocationCoordinate2D] {
        decodedTrack.map {
            CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
        }
    }

    /// GPX 生成用の完全トラックデータ
    var decodedTrack: [[Double]] {
        (try? JSONDecoder().decode([[Double]].self, from: trackJSON)) ?? []
    }
}
