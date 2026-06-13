import CoreLocation
import Foundation

/// バックエンドサーバの Valhalla API を使った自転車専用ルーティング
struct ValhallaRouteProvider: RouteProvider {
    func fetchRoute(
        waypoints: [CLLocationCoordinate2D]
    ) async throws -> NavigationRoute {
        guard waypoints.count >= 2 else {
            throw ValhallaRouteProviderError.tooFewWaypoints
        }

        let requestBody = ValhallaService.RouteRequest(
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
            body: requestBody
        )

        guard let leg = response.trip.legs.first else {
            throw ValhallaRouteProviderError.noLegs
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

    enum ValhallaRouteProviderError: LocalizedError {
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
