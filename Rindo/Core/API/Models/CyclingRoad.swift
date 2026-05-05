import CoreLocation
import Foundation

/// バンドル済み GeoJSON FeatureCollection をパースするモデル
struct CyclingRoadsResponse: Codable, Sendable {
    let type: String
    let features: [CyclingRoadFeature]
}

struct CyclingRoadFeature: Codable, Sendable, Identifiable {
    let type: String
    let properties: CyclingRoadProperties
    let geometry: CyclingRoadGeometry

    var id: Int { properties.fid }

    /// ルート全体の CLLocationCoordinate2D 配列
    var coordinates: [CLLocationCoordinate2D] {
        geometry.coordinates.flatMap { line in
            line.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
        }
    }

    /// 標高API用の [[lon, lat]] 配列
    var coordinatePairs: [[Double]] {
        geometry.coordinates.flatMap { line in
            line.filter { $0.count >= 2 }
        }
    }

    /// Haversine によるルート総距離（メートル）
    var lengthMeters: Double {
        let coords = coordinates
        guard coords.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<coords.count {
            let prev = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let curr = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            total += prev.distance(from: curr)
        }
        return total
    }
}

struct CyclingRoadProperties: Codable, Sendable {
    let fid: Int
    let name: String
    let ward: String
    let roadType: String
    let source: String
    let largeScale: Bool?

    var isExclusive: Bool { roadType.trimmingCharacters(in: .whitespaces) == "exclusive" }
    var isLargeScale: Bool { largeScale == true }

    var roadTypeLabel: String {
        isExclusive ? "自転車歩行者専用" : "一般道路共用"
    }

    enum CodingKeys: String, CodingKey {
        case fid, name, ward, source
        case roadType = "road_type"
        case largeScale = "large_scale"
    }
}

/// MultiLineString geometry
struct CyclingRoadGeometry: Codable, Sendable {
    let type: String
    let coordinates: [[[Double]]]
}
