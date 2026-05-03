import CoreLocation
import Foundation

// MARK: - Valhalla Response Models

struct ValhallaRouteResponse: Codable, Sendable {
    let trip: ValhallaTrip
}

struct ValhallaTrip: Codable, Sendable {
    let legs: [ValhallaLeg]
    let summary: ValhallaSummary
}

struct ValhallaLeg: Codable, Sendable {
    let maneuvers: [ValhallaManeuver]
    let shape: String
}

struct ValhallaSummary: Codable, Sendable {
    let length: Double  // km
    let time: Double    // seconds
}

/// CodingKeys 不要 — APIClient の .convertFromSnakeCase が自動変換
struct ValhallaManeuver: Codable, Sendable {
    let type: Int
    let instruction: String
    let verbalPreTransitionInstruction: String?
    let verbalPostTransitionInstruction: String?
    let bearingAfter: Int?
    let length: Double  // km
    let time: Double    // seconds
    let beginShapeIndex: Int
    let endShapeIndex: Int
    let streetNames: [String]?
}

// MARK: - Parsed Route (ready for navigation)

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

// MARK: - Service

enum ValhallaService {
    struct RouteRequest: Encodable {
        let locations: [Location]
        let costing: String
        let costing_options: CostingOptions
        let directions_options: DirectionsOptions

        struct Location: Encodable {
            let lon: Double
            let lat: Double
        }
        struct CostingOptions: Encodable {
            let bicycle: BicycleOptions
        }
        struct BicycleOptions: Encodable {
            let bicycle_type: String
            let use_roads: Double
            let use_trails: Double
        }
        struct DirectionsOptions: Encodable {
            let language: String
        }
    }

    /// Valhalla に bicycle ルートをリクエストし、ナビ用に解析済みのルートを返す
    static func fetchRoute(
        waypoints: [CLLocationCoordinate2D]
    ) async throws -> NavigationRoute {
        guard waypoints.count >= 2 else {
            throw ValhallaError.tooFewWaypoints
        }

        let request = RouteRequest(
            locations: waypoints.map { .init(lon: $0.longitude, lat: $0.latitude) },
            costing: "bicycle",
            costing_options: .init(bicycle: .init(
                bicycle_type: "Road",
                use_roads: 0.1,
                use_trails: 1.0
            )),
            directions_options: .init(language: "ja")
        )

        let response = try await APIClient.shared.post(
            ValhallaRouteResponse.self,
            path: "/api/valhalla/route",
            body: request,
            baseURL: AppConfig.caddyBaseURL
        )

        guard let leg = response.trip.legs.first else {
            throw ValhallaError.noLegs
        }

        let coordinates = PolylineDecoder.decode(leg.shape)

        let maneuvers: [NavigationManeuver] = leg.maneuvers.map { m in
            let coord = m.beginShapeIndex < coordinates.count
                ? coordinates[m.beginShapeIndex]
                : coordinates.last!
            return NavigationManeuver(
                type: m.type,
                instruction: m.instruction,
                voiceInstruction: m.verbalPreTransitionInstruction ?? m.instruction,
                distanceKm: m.length,
                timeSeconds: m.time,
                coordinate: coord,
                bearingAfter: m.bearingAfter ?? 0
            )
        }

        return NavigationRoute(
            coordinates: coordinates,
            maneuvers: maneuvers,
            totalDistanceKm: response.trip.summary.length,
            totalTimeSeconds: response.trip.summary.time
        )
    }

    enum ValhallaError: LocalizedError {
        case tooFewWaypoints
        case noLegs

        var errorDescription: String? {
            switch self {
            case .tooFewWaypoints: "ルートには 2 点以上必要です"
            case .noLegs: "ルートが見つかりません"
            }
        }
    }
}
