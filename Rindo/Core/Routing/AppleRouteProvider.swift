import CoreLocation
import MapKit

/// Apple Maps（MKDirections .walking）を使ったルーティング
/// サーバー不要で動作する標準モード
struct AppleRouteProvider: RouteProvider {

    func fetchRoute(
        waypoints: [CLLocationCoordinate2D]
    ) async throws -> NavigationRoute {
        guard waypoints.count >= 2 else {
            throw AppleRouteError.tooFewWaypoints
        }

        // 複数ウェイポイントを順にペアで繋ぎ、結合する
        var allCoordinates: [CLLocationCoordinate2D] = []
        var allManeuvers: [NavigationManeuver] = []
        var totalDistanceKm = 0.0
        var totalTimeSeconds = 0.0

        for i in 0..<(waypoints.count - 1) {
            let segment = try await fetchSegment(from: waypoints[i], to: waypoints[i + 1])
            if allCoordinates.isEmpty {
                allCoordinates.append(contentsOf: segment.coordinates)
            } else {
                allCoordinates.append(contentsOf: segment.coordinates.dropFirst())
            }
            // マニューバ座標のオフセット不要（各セグメント内で完結）
            allManeuvers.append(contentsOf: segment.maneuvers)
            totalDistanceKm += segment.totalDistanceKm
            totalTimeSeconds += segment.totalTimeSeconds
        }

        // 所要時間を自転車速度で補正（徒歩 5km/h → 自転車 18km/h）
        let cyclingTimeSeconds = totalTimeSeconds * (5.0 / 18.0)

        return NavigationRoute(
            coordinates: allCoordinates,
            maneuvers: allManeuvers,
            totalDistanceKm: totalDistanceKm,
            totalTimeSeconds: cyclingTimeSeconds
        )
    }

    // MARK: - Private

    private func fetchSegment(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async throws -> NavigationRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        guard let mkRoute = response.routes.first else {
            throw AppleRouteError.noRouteFound
        }

        let coordinates = extractCoordinates(from: mkRoute.polyline)
        let maneuvers = convertSteps(mkRoute.steps, routeCoordinates: coordinates)

        return NavigationRoute(
            coordinates: coordinates,
            maneuvers: maneuvers,
            totalDistanceKm: mkRoute.distance / 1000,
            totalTimeSeconds: mkRoute.expectedTravelTime
        )
    }

    private func extractCoordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords
    }

    private func convertSteps(
        _ steps: [MKRoute.Step],
        routeCoordinates: [CLLocationCoordinate2D]
    ) -> [NavigationManeuver] {
        var maneuvers: [NavigationManeuver] = []

        for (i, step) in steps.enumerated() {
            // 空のインストラクション（最初の「出発」ステップ等）はスキップ
            guard !step.instructions.isEmpty else { continue }

            let stepCoords = extractCoordinates(from: step.polyline)
            let coordinate = stepCoords.first ?? routeCoordinates.first!

            let type: Int
            let bearingAfter: Int

            if i == 0 {
                type = 1 // Start
                bearingAfter = calculateBearing(from: coordinate, to: stepCoords.count > 1 ? stepCoords[1] : coordinate)
            } else if i == steps.count - 1 && step.instructions.contains("目的地") {
                type = 4 // Destination
                bearingAfter = 0
            } else {
                type = inferManeuverType(instruction: step.instructions, stepCoords: stepCoords, previousStep: i > 0 ? steps[i - 1] : nil)
                bearingAfter = stepCoords.count > 1
                    ? calculateBearing(from: stepCoords[0], to: stepCoords[1])
                    : 0
            }

            maneuvers.append(NavigationManeuver(
                type: type,
                instruction: step.instructions,
                voiceInstruction: step.instructions,
                distanceKm: step.distance / 1000,
                timeSeconds: step.distance / 1000 / 18 * 3600, // 自転車 18km/h 換算
                coordinate: coordinate,
                bearingAfter: bearingAfter
            ))
        }

        // 目的地マニューバが無ければ追加
        if maneuvers.last.map({ !ManeuverParser.isDestination($0.type) }) ?? true,
           let lastCoord = routeCoordinates.last {
            maneuvers.append(NavigationManeuver(
                type: 4,
                instruction: "目的地に到着",
                voiceInstruction: "目的地に到着しました",
                distanceKm: 0,
                timeSeconds: 0,
                coordinate: lastCoord,
                bearingAfter: 0
            ))
        }

        return maneuvers
    }

    /// MKRoute.Step の instruction テキストから Valhalla 互換の maneuver type を推定
    private func inferManeuverType(
        instruction: String,
        stepCoords: [CLLocationCoordinate2D],
        previousStep: MKRoute.Step?
    ) -> Int {
        // 日本語キーワードマッチング
        if instruction.contains("右に曲") || instruction.contains("右折") {
            return 10 // Right
        }
        if instruction.contains("左に曲") || instruction.contains("左折") {
            return 15 // Left
        }
        if instruction.contains("斜め右") || instruction.contains("やや右") {
            return 9 // SlightRight
        }
        if instruction.contains("斜め左") || instruction.contains("やや左") {
            return 16 // SlightLeft
        }
        if instruction.contains("Uターン") || instruction.contains("折り返") {
            return 12 // UturnRight
        }
        if instruction.contains("直進") || instruction.contains("まっすぐ") {
            return 8 // Continue
        }
        if instruction.contains("合流") {
            return 25 // Merge
        }

        // テキストで判別できない場合は方位角変化から推定
        if let prevCoords = previousStep.map({ extractCoordinates(from: $0.polyline) }),
           prevCoords.count >= 2, stepCoords.count >= 2 {
            let prevBearing = calculateBearing(from: prevCoords[prevCoords.count - 2], to: prevCoords.last!)
            let nextBearing = calculateBearing(from: stepCoords[0], to: stepCoords[1])
            let delta = normalizeAngle(nextBearing - prevBearing)

            if abs(delta) < 20 { return 8 }       // Continue
            if delta > 0 && delta < 60 { return 9 }  // SlightRight
            if delta >= 60 && delta < 130 { return 10 }  // Right
            if delta >= 130 { return 12 }             // UturnRight
            if delta < 0 && delta > -60 { return 16 } // SlightLeft
            if delta <= -60 && delta > -130 { return 15 } // Left
            if delta <= -130 { return 13 }            // UturnLeft
        }

        return 8 // デフォルト: Continue
    }

    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Int {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return Int((bearing + 360).truncatingRemainder(dividingBy: 360))
    }

    private func normalizeAngle(_ angle: Int) -> Int {
        var a = angle % 360
        if a > 180 { a -= 360 }
        if a < -180 { a += 360 }
        return a
    }

    enum AppleRouteError: LocalizedError {
        case tooFewWaypoints
        case noRouteFound

        var errorDescription: String? {
            switch self {
            case .tooFewWaypoints: "ルートには 2 点以上必要です"
            case .noRouteFound: "ルートが見つかりません"
            }
        }
    }
}
