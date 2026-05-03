import CoreLocation
import Foundation
import SwiftData

@Model
final class ImportedRoute {
    var id: UUID
    var name: String
    var importedAt: Date
    /// 座標配列を JSON で保存: [[lon, lat, ele?], ...]
    var pointsJSON: Data
    var totalDistanceKm: Double

    init(name: String, points: [GPXParser.TrackPoint]) {
        self.id = UUID()
        self.name = name
        self.importedAt = Date()

        // 座標 + 標高を JSON 配列に変換
        let encoded: [[Double]] = points.map { pt in
            if let ele = pt.elevation {
                return [pt.coordinate.longitude, pt.coordinate.latitude, ele]
            } else {
                return [pt.coordinate.longitude, pt.coordinate.latitude]
            }
        }
        self.pointsJSON = (try? JSONEncoder().encode(encoded)) ?? Data()

        // 総距離を計算
        var distance = 0.0
        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i - 1].coordinate.latitude,
                                  longitude: points[i - 1].coordinate.longitude)
            let curr = CLLocation(latitude: points[i].coordinate.latitude,
                                  longitude: points[i].coordinate.longitude)
            distance += prev.distance(from: curr)
        }
        self.totalDistanceKm = distance / 1000
    }

    /// 座標配列を復元
    var coordinates: [CLLocationCoordinate2D] {
        guard let decoded = try? JSONDecoder().decode([[Double]].self, from: pointsJSON) else {
            return []
        }
        return decoded.compactMap { arr in
            guard arr.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: arr[1], longitude: arr[0])
        }
    }

    /// 標高データを復元（ele タグがあった場合）
    var elevations: [Double]? {
        guard let decoded = try? JSONDecoder().decode([[Double]].self, from: pointsJSON) else {
            return nil
        }
        let eles = decoded.compactMap { arr -> Double? in
            arr.count >= 3 ? arr[2] : nil
        }
        // 全ポイントに標高がある場合のみ返す
        return eles.count == decoded.count ? eles : nil
    }

    /// GeoJSON coordinates 形式（[[lon, lat], ...]）
    var geoJSONCoordinates: [[Double]] {
        guard let decoded = try? JSONDecoder().decode([[Double]].self, from: pointsJSON) else {
            return []
        }
        return decoded.map { arr in
            Array(arr.prefix(2))
        }
    }
}
