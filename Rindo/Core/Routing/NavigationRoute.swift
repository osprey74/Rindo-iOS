import CoreLocation

/// ルーティングエンジン共通のルート表現（Valhalla / Apple Maps 両方で使用）
struct NavigationRoute: Sendable {
    let coordinates: [CLLocationCoordinate2D]
    let maneuvers: [NavigationManeuver]
    let totalDistanceKm: Double
    let totalTimeSeconds: Double
}

struct NavigationManeuver: Sendable {
    let type: Int
    let instruction: String
    let voiceInstruction: String
    let distanceKm: Double
    let timeSeconds: Double
    let coordinate: CLLocationCoordinate2D
    let bearingAfter: Int
}
