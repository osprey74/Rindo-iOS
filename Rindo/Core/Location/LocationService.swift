import CoreLocation
import Foundation

@Observable
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    // 現在位置
    private(set) var currentLocation: CLLocation?
    /// 進行方向（度、北=0）。停車中は直前の有効値を保持
    private(set) var course: Double = 0
    /// 速度 (km/h)
    private(set) var speedKmh: Double = 0
    /// 累積移動距離 (m)
    private(set) var totalDistanceM: Double = 0
    /// 走行中フラグ
    private(set) var isTracking = false

    // ルート逸脱
    private(set) var isOffRoute = false
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private static let deviationThresholdM = 30.0
    /// 逸脱通知コールバック
    var onDeviation: (() -> Void)?

    // 内部
    private var lastLocation: CLLocation?

    override nonisolated init() {
        super.init()
        Task { @MainActor in
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.activityType = .otherNavigation
        }
    }

    func startTracking() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        isTracking = true
        totalDistanceM = 0
        lastLocation = nil
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        isTracking = false
    }

    /// ナビ対象ルートを設定（逸脱検知用）
    func setRoute(_ coordinates: [CLLocationCoordinate2D]) {
        routeCoordinates = coordinates
        isOffRoute = false
    }

    func clearRoute() {
        routeCoordinates = []
        isOffRoute = false
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            handleLocationUpdate(location)
        }
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        currentLocation = location

        // 速度（負値は無効）
        if location.speed >= 0 {
            speedKmh = location.speed * 3.6
        }

        // 進行方向（有効値のみ更新、停車中は直前値を保持）
        if location.course >= 0 && location.speed > 0.5 {
            course = location.course
        }

        // 累積距離
        if let last = lastLocation {
            totalDistanceM += location.distance(from: last)
        }
        lastLocation = location

        // ルート逸脱検知
        checkDeviation(location)
    }

    private func checkDeviation(_ location: CLLocation) {
        guard !routeCoordinates.isEmpty else {
            isOffRoute = false
            return
        }

        let minDistance = routeCoordinates
            .map { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) }
            .min() ?? 0

        let wasOffRoute = isOffRoute
        isOffRoute = minDistance > Self.deviationThresholdM

        // 逸脱に入った瞬間のみ通知
        if isOffRoute && !wasOffRoute {
            onDeviation?()
        }
    }
}
