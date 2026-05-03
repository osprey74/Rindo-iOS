import Foundation
import CoreLocation

struct RoutesResponse: Codable, Sendable {
    let routes: [SavedRoute]
}

struct SavedRoute: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let waypoints: [LonLat]
    let geometry: GeoJSONLineString
    let distanceKm: Double?
    let durationMin: Double?
    let ascentM: Double?
    let descentM: Double?
    let createdAt: String
    let updatedAt: String

    /// ルート全体の CLLocationCoordinate2D 配列（地図描画用）
    var coordinates: [CLLocationCoordinate2D] {
        geometry.coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }
}

struct LonLat: Codable, Sendable {
    let lon: Double
    let lat: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct GeoJSONLineString: Codable, Sendable {
    let type: String
    let coordinates: [[Double]]
}
