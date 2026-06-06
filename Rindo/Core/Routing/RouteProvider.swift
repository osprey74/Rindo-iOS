import CoreLocation

/// ルーティングエンジンの抽象化プロトコル
/// Apple Maps（標準モード）と Valhalla（フルスペック）を切り替え可能にする
protocol RouteProvider: Sendable {
    /// 2点間のルートを取得
    func fetchRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async throws -> NavigationRoute

    /// 複数ウェイポイント経由のルートを取得
    func fetchRoute(
        waypoints: [CLLocationCoordinate2D]
    ) async throws -> NavigationRoute
}

extension RouteProvider {
    /// デフォルト実装: 2点を waypoints として委譲
    func fetchRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async throws -> NavigationRoute {
        try await fetchRoute(waypoints: [from, to])
    }
}
