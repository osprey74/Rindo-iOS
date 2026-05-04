import CoreLocation
import Foundation

/// ターンバイターンナビゲーションの進捗管理
/// 現在地からルート上の位置を追跡し、マニューバ接近時に音声案内をトリガする
@Observable
@MainActor
final class NavigationManager {
    // 状態
    private(set) var isActive = false
    private(set) var route: NavigationRoute?
    private(set) var currentManeuverIndex = 0
    private(set) var distanceToNextManeuverM: Double = 0
    private(set) var remainingDistanceKm: Double = 0
    private(set) var remainingTimeSeconds: Double = 0

    /// 現在のマニューバ（次の分岐）
    var currentManeuver: NavigationManeuver? {
        guard let route, currentManeuverIndex < route.maneuvers.count else { return nil }
        return route.maneuvers[currentManeuverIndex]
    }

    /// 自動再ルート中フラグ
    private(set) var isRerouting = false

    // 依存
    let voiceGuide = VoiceGuide()
    private var lastRerouteTime: Date?
    private var totalTraveledM: Double = 0
    private var lastUpdateLocation: CLLocation?
    /// ルート総距離の半分以上走るまで到着判定しない
    private var arrivalThresholdM: Double = 0
    private static let rerouteCooldownSeconds: TimeInterval = 30
    private static let deviationThresholdM: Double = 30

    // 音声トリガ距離閾値（m） — RideMode により外部から設定可能
    var voiceTriggerDistances: [Double] = [200, 100, 50]

    // 再ルート用ウェイポイント
    private var originalWaypoints: [CLLocationCoordinate2D] = []

    // MARK: - Start / Stop

    func start(route: NavigationRoute, waypoints: [CLLocationCoordinate2D]) {
        self.route = route
        self.originalWaypoints = waypoints
        currentManeuverIndex = findFirstNonStartManeuver()
        remainingDistanceKm = route.totalDistanceKm
        remainingTimeSeconds = route.totalTimeSeconds
        isActive = true
        totalTraveledM = 0
        lastUpdateLocation = nil
        arrivalThresholdM = route.totalDistanceKm * 1000 * 0.5
        voiceGuide.reset()

        // 開始音声
        if let first = currentManeuver {
            voiceGuide.speak(first.voiceInstruction, key: "start")
        }
    }

    func stop() {
        isActive = false
        route = nil
        voiceGuide.stop()
    }

    // MARK: - Location Update

    /// 現在地を受け取りナビ状態を更新。再ルートが必要なら true を返す
    func updateLocation(_ location: CLLocation) -> RerouteRequest? {
        guard isActive, let route else { return nil }

        // 走行距離を累積（到着判定に使用）
        if let last = lastUpdateLocation {
            totalTraveledM += location.distance(from: last)
        }
        lastUpdateLocation = location

        let current = location.coordinate
        let coords = route.coordinates

        // ルート上の最寄り点を見つける
        let (nearestIndex, nearestDistance) = findNearestPoint(to: current, on: coords)

        // 逸脱チェック（ルート総距離の10%以上走るまでは逸脱判定しない — 周回ルート対策）
        let minTravelForDeviation = route.totalDistanceKm * 1000 * 0.1
        if nearestDistance > Self.deviationThresholdM && totalTraveledM > minTravelForDeviation {
            return handleDeviation(currentLocation: current)
        }

        // 次マニューバまでの距離を計算
        updateManeuverProgress(currentIndex: nearestIndex, currentCoord: current, route: route)

        // 残り距離・時間を概算更新
        updateRemaining(currentIndex: nearestIndex, route: route)

        return nil
    }

    struct RerouteRequest {
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
    }

    // MARK: - Private

    private func findFirstNonStartManeuver() -> Int {
        guard let route else { return 0 }
        // type 1/2/3 = Start 系、最初の非 Start マニューバにスキップ
        for (i, m) in route.maneuvers.enumerated() {
            if !(1...3).contains(m.type) { return i }
        }
        return min(1, route.maneuvers.count - 1)
    }

    private func findNearestPoint(
        to coord: CLLocationCoordinate2D,
        on routeCoords: [CLLocationCoordinate2D]
    ) -> (index: Int, distance: Double) {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        var minDist = Double.infinity
        var minIndex = 0
        for (i, rc) in routeCoords.enumerated() {
            let d = loc.distance(from: CLLocation(latitude: rc.latitude, longitude: rc.longitude))
            if d < minDist {
                minDist = d
                minIndex = i
            }
        }
        return (minIndex, minDist)
    }

    private func updateManeuverProgress(
        currentIndex: Int,
        currentCoord: CLLocationCoordinate2D,
        route: NavigationRoute
    ) {
        // 次のマニューバに進んだか判定
        while currentManeuverIndex < route.maneuvers.count - 1 {
            // 現在のマニューバ地点を通過したら次に進む
            let currentManeuverCoord = route.maneuvers[currentManeuverIndex].coordinate
            let distToCurrent = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
                .distance(from: CLLocation(latitude: currentManeuverCoord.latitude, longitude: currentManeuverCoord.longitude))

            if distToCurrent < 20 && currentManeuverIndex < route.maneuvers.count - 1 {
                currentManeuverIndex += 1
                voiceGuide.reset() // 新しいマニューバ用に発話履歴リセット
            } else {
                break
            }
        }

        // 次マニューバまでの距離
        if let next = currentManeuver {
            let nextLoc = CLLocation(latitude: next.coordinate.latitude, longitude: next.coordinate.longitude)
            let currentLoc = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
            distanceToNextManeuverM = currentLoc.distance(from: nextLoc)

            // 音声トリガ
            triggerVoiceIfNeeded(maneuver: next, distanceM: distanceToNextManeuverM)
        }
    }

    private func triggerVoiceIfNeeded(maneuver: NavigationManeuver, distanceM: Double) {
        for threshold in voiceTriggerDistances {
            if distanceM <= threshold {
                let key = "m\(currentManeuverIndex)_\(Int(threshold))m"
                let distText = threshold >= 100
                    ? "\(Int(threshold))メートル先、"
                    : "まもなく、"
                voiceGuide.speak(distText + maneuver.voiceInstruction, key: key)
                break // 最も近い閾値のみ
            }
        }

        // 到着判定（ルート総距離の半分以上走ってから判定 — 周回ルート対策）
        if ManeuverParser.isDestination(maneuver.type) && distanceM < 30 && totalTraveledM > arrivalThresholdM {
            voiceGuide.speak("目的地に到着しました。", key: "arrival")
        }
    }

    private func handleDeviation(currentLocation: CLLocationCoordinate2D) -> RerouteRequest? {
        // クールダウン判定
        if let last = lastRerouteTime,
           Date().timeIntervalSince(last) < Self.rerouteCooldownSeconds {
            return nil
        }

        lastRerouteTime = Date()
        isRerouting = true

        voiceGuide.speak("ルートを再検索しています。", key: "reroute_\(Date().timeIntervalSince1970)")

        // 最終目的地
        guard let dest = originalWaypoints.last else { return nil }
        return RerouteRequest(from: currentLocation, to: dest)
    }

    /// 再ルート結果を適用
    func applyReroute(_ newRoute: NavigationRoute) {
        route = newRoute
        currentManeuverIndex = findFirstNonStartManeuver()
        remainingDistanceKm = newRoute.totalDistanceKm
        remainingTimeSeconds = newRoute.totalTimeSeconds
        isRerouting = false
        voiceGuide.reset()

        if let first = currentManeuver {
            voiceGuide.speak(first.voiceInstruction, key: "reroute_start")
        }
    }

    func rerouteFailed() {
        isRerouting = false
    }

    private func updateRemaining(currentIndex: Int, route: NavigationRoute) {
        // 残りマニューバの距離・時間を合算
        var dist = 0.0
        var time = 0.0
        for i in currentManeuverIndex..<route.maneuvers.count {
            dist += route.maneuvers[i].distanceKm
            time += route.maneuvers[i].timeSeconds
        }
        remainingDistanceKm = dist
        remainingTimeSeconds = time
    }
}
