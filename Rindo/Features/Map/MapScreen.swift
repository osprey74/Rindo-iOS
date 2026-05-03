import AudioToolbox
import CoreLocation
import SwiftUI

struct MapScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var modelContext

    // レイヤーデータ
    @State private var cyclingRoadsData: Data?
    @State private var osmCyclewaysData: Data?
    @State private var bicycleRoutesData: Data?

    // サーバ連携ルート・地点
    @State private var selectedRoute: SavedRoute?
    @State private var savedLocations: [SavedLocation] = []

    // GPX インポートルート（ナビ対象）
    @State private var activeImportedRoute: ImportedRoute?

    // ナビゲーション用の共通座標（サーバルートまたはGPXルート）
    @State private var navigationCoordinates: [CLLocationCoordinate2D] = []

    // 位置情報・ナビ・走行記録
    @State private var locationService = LocationService()
    @State private var rideRecorder = RideRecorder()
    @State private var isNavigating = false
    @State private var navManager = NavigationManager()
    @State private var valhallaRoute: NavigationRoute?
    @State private var showSimpleNav = false

    // 標高
    @State private var elevationProfile: ElevationProfile?
    @State private var isLoadingElevation = false

    // 地図制御
    @State private var focusCoordinate: CLLocationCoordinate2D?
    @State private var navZoomLevel: Double?

    // シート表示
    @State private var showRoutes = false
    @State private var showLocations = false
    @State private var showRideHistory = false
    @State private var showSettings = false

    // エラー
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            // 地図
            RindoMapView(
                cyclingRoadsData: cyclingRoadsData,
                osmCyclewaysData: osmCyclewaysData,
                bicycleRoutesData: bicycleRoutesData,
                selectedRoute: selectedRoute,
                savedLocations: savedLocations,
                focusCoordinate: focusCoordinate,
                focusZoomLevel: navZoomLevel,
                navigationCoordinates: navigationCoordinates,
                locationService: locationService,
                isNavigating: isNavigating,
                recordedTrack: rideRecorder.isRecording ? rideRecorder.trackPoints : []
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                // 逸脱警告
                if locationService.isOffRoute && isNavigating {
                    Text("ルートから外れています")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.red, in: Capsule())
                }

                // 走行情報パネル（ナビ中 or 走行記録中）
                if isNavigating || rideRecorder.isRecording {
                    NavigationInfoPanel(
                        speedKmh: rideRecorder.isRecording ? rideRecorder.speedKmh : locationService.speedKmh,
                        distanceM: rideRecorder.isRecording ? rideRecorder.totalDistanceM : locationService.totalDistanceM,
                        elapsed: rideRecorder.elapsedSeconds,
                        isOffRoute: locationService.isOffRoute
                    )
                    .padding(.horizontal, 8)
                }

                // ターンバイターンナビ（Valhalla ルート時のみ）
                if navManager.isActive {
                    TurnByTurnPanel(
                        maneuver: navManager.currentManeuver,
                        distanceToNextM: navManager.distanceToNextManeuverM,
                        remainingDistanceKm: navManager.remainingDistanceKm,
                        remainingTimeSeconds: navManager.remainingTimeSeconds,
                        isRerouting: navManager.isRerouting
                    )
                }

                // ルート情報バー
                if let route = selectedRoute {
                    serverRouteInfoBar(route)
                } else if let imported = activeImportedRoute {
                    importedRouteInfoBar(imported)
                }
            }

        }
        .fullScreenCover(isPresented: $showSimpleNav) {
            SimpleNavView(
                maneuver: navManager.currentManeuver,
                distanceToNextM: navManager.distanceToNextManeuverM,
                remainingDistanceKm: navManager.remainingDistanceKm,
                speedKmh: locationService.speedKmh,
                onDismiss: { showSimpleNav = false }
            )
        }
        .overlay(alignment: .topLeading) {
            // 左上ボタン群
            HStack(alignment: .top, spacing: 8) {
                verticalButtons
                actionButtons
            }
            .padding(.leading)
            .padding(.top, 60)
        }
        .overlay(alignment: .top) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 60)
                    .onTapGesture { errorMessage = nil }
            }
        }
        .sheet(isPresented: $showRoutes) {
            SavedRoutesPanel { route in selectServerRoute(route) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLocations) {
            SavedLocationsPanel { location in applyFocus(location.coordinate) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showRideHistory) {
            RideHistoryPanel { ride in
                // 走行履歴からトラックを地図に表示
                clearRoute()
                navigationCoordinates = ride.coordinates
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onSelectImportedRoute: { route in
                selectImportedRoute(route)
            })
            .environment(auth)
        }
        .task {
            await loadAllLayers()
            setupDeviationFeedback()
            setupNavLocationUpdates()
        }
    }

    // MARK: - Button Layout

    /// 縦列（左端）: ルート → 地点 → 現在地 → 設定
    private var verticalButtons: some View {
        VStack(spacing: 8) {
            if auth.isAuthenticated {
                sideButton(icon: "map", label: "ルート") {
                    showRoutes = true
                }
                sideButton(icon: "mappin.and.ellipse", label: "地点") {
                    showLocations = true
                }
            }
            sideButton(icon: "location.fill", label: "現在地") {
                goToCurrentLocation()
            }
            sideButton(icon: "gearshape", label: "設定") {
                showSettings = true
            }
        }
    }

    /// 横列（ルートの右隣）: ナビ → 記録 → 履歴
    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // ナビ（ルート有効時のみ）
                if hasActiveRoute && !isNavigating {
                    sideButton(icon: "location.north.fill", label: "ナビ") {
                        startNavigation()
                    }
                } else if isNavigating {
                    // 簡易ナビ切替（Valhallaルート時のみ）
                    if navManager.isActive {
                        sideButton(icon: "moon.fill", label: "簡易") {
                            showSimpleNav = true
                        }
                    }
                    sideButton(icon: "xmark", label: "ナビ終了") {
                        stopNavigation()
                    }
                }

                // 記録
                if rideRecorder.state == .idle {
                    sideButton(icon: "record.circle", label: "記録") {
                        startRideRecording()
                    }
                } else if rideRecorder.state == .recording {
                    sideButton(icon: "pause.fill", label: "一時停止") {
                        rideRecorder.pause()
                    }
                    sideButton(icon: "stop.fill", label: "記録停止") {
                        stopRideRecording()
                    }
                } else if rideRecorder.state == .paused {
                    sideButton(icon: "play.fill", label: "再開") {
                        rideRecorder.resume()
                    }
                    sideButton(icon: "stop.fill", label: "記録停止") {
                        stopRideRecording()
                    }
                }

                // 履歴
                sideButton(icon: "list.bullet.rectangle", label: "履歴") {
                    showRideHistory = true
                }
            }
        }
    }

    private func sideButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.body)
                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Route Info Bars

    private var hasActiveRoute: Bool {
        selectedRoute != nil || activeImportedRoute != nil
    }

    private func serverRouteInfoBar(_ route: SavedRoute) -> some View {
        routeInfoBar(
            name: route.name,
            details: {
                HStack(spacing: 12) {
                    if let km = route.distanceKm { Text(String(format: "%.1f km", km)) }
                    if let min = route.durationMin { Text(formatDuration(min)) }
                    if let ascent = route.ascentM { Text(String(format: "↑%.0f m", ascent)) }
                }
            },
            onDismiss: { clearRoute() }
        )
    }

    private func importedRouteInfoBar(_ route: ImportedRoute) -> some View {
        routeInfoBar(
            name: route.name,
            details: {
                HStack(spacing: 12) {
                    Text(String(format: "%.1f km", route.totalDistanceKm))
                    Text("GPX")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: Capsule())
                }
            },
            onDismiss: { clearRoute() }
        )
    }

    private func routeInfoBar<D: View>(name: String, @ViewBuilder details: () -> D, onDismiss: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    details()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { withAnimation { onDismiss() } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            if let profile = elevationProfile {
                ElevationChart(profile: profile)
            } else if isLoadingElevation {
                ProgressView("標高読み込み中...")
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Ride Recording

    private func startRideRecording() {
        locationService.rideRecorder = rideRecorder
        rideRecorder.start()
        if !locationService.isTracking {
            locationService.startTracking()
        }
    }

    private func stopRideRecording() {
        guard let summary = rideRecorder.stop() else { return }
        locationService.rideRecorder = nil
        if !isNavigating {
            locationService.stopTracking()
        }

        // SwiftData に保存
        let rideLog = RideLog(summary: summary)
        modelContext.insert(rideLog)

        // サーバアップロード（ログイン時のみ、バックグラウンドで）
        if auth.isAuthenticated {
            Task { await uploadRide(rideLog) }
        }
    }

    private func uploadRide(_ ride: RideLog) async {
        struct RidePayload: Encodable {
            let started_at: String
            let ended_at: String
            let distance_km: Double
            let duration_min: Double
            let ascent_m: Double
            let descent_m: Double
            let max_speed_kmh: Double
            let avg_speed_kmh: Double
            let calories_kcal: Double
            let track: [[Double]]
        }

        let iso = ISO8601DateFormatter()
        let payload = RidePayload(
            started_at: iso.string(from: ride.startedAt),
            ended_at: iso.string(from: ride.endedAt),
            distance_km: ride.distanceKm,
            duration_min: ride.durationMin,
            ascent_m: ride.ascentM,
            descent_m: ride.descentM,
            max_speed_kmh: ride.maxSpeedKmh,
            avg_speed_kmh: ride.avgSpeedKmh,
            calories_kcal: ride.caloriesKcal,
            track: ride.decodedTrack
        )

        do {
            struct UploadResponse: Decodable { let id: Int }
            _ = try await APIClient.shared.post(UploadResponse.self, path: "/api/rides", body: payload)
            ride.uploaded = true
        } catch {
            // アップロード失敗は次回リトライ（静かに失敗）
        }
    }

    // MARK: - Navigation

    private func startNavigation() {
        locationService.setRoute(navigationCoordinates)
        if !locationService.isTracking {
            locationService.startTracking()
        }
        isNavigating = true

        // Valhalla ルートがある場合はターンバイターンナビを開始
        if let vRoute = valhallaRoute {
            navManager.start(
                route: vRoute,
                waypoints: selectedRoute?.waypoints.map(\.coordinate) ?? navigationCoordinates
            )
        }

        // ナビ開始時に現在地付近をズームイン（zoom 17）
        if let loc = locationService.currentLocation {
            applyFocus(loc.coordinate, zoom: 17)
        }
    }

    private func stopNavigation() {
        isNavigating = false
        showSimpleNav = false
        navManager.stop()
        locationService.clearRoute()
        if !rideRecorder.isRecording {
            locationService.stopTracking()
        }
    }

    private func setupDeviationFeedback() {
        locationService.onDeviation = { [self] in
            let feedback = UIImpactFeedbackGenerator(style: .heavy)
            feedback.impactOccurred()
            AudioServicesPlaySystemSound(1521)

            // Valhalla ナビ中は自動再ルート
            if navManager.isActive, let loc = locationService.currentLocation {
                if let request = navManager.updateLocation(loc) {
                    Task { await performReroute(request) }
                }
            }
        }
    }

    private func setupNavLocationUpdates() {
        locationService.onLocationUpdate = { [self] location in
            guard navManager.isActive else { return }
            if let request = navManager.updateLocation(location) {
                Task { await performReroute(request) }
            }
        }
    }

    private func performReroute(_ request: NavigationManager.RerouteRequest) async {
        do {
            let newRoute = try await ValhallaService.fetchRoute(
                waypoints: [request.from, request.to]
            )
            navManager.applyReroute(newRoute)
            valhallaRoute = newRoute
            navigationCoordinates = newRoute.coordinates
            locationService.setRoute(newRoute.coordinates)
        } catch {
            navManager.rerouteFailed()
        }
    }

    // MARK: - Route Selection

    private func selectServerRoute(_ route: SavedRoute) {
        clearRoute()
        selectedRoute = route
        navigationCoordinates = route.coordinates

        // Valhalla ルートを取得（ターンバイターンナビ用）
        Task {
            do {
                valhallaRoute = try await ValhallaService.fetchRoute(
                    waypoints: route.waypoints.map(\.coordinate)
                )
                // Valhalla のルート形状で上書き（より正確）
                if let vRoute = valhallaRoute {
                    navigationCoordinates = vRoute.coordinates
                }
            } catch {
                // Valhalla 失敗時はライン追従ナビのみ
                valhallaRoute = nil
                errorMessage = "Valhalla: \(error.localizedDescription)"
            }
        }

        Task {
            isLoadingElevation = true
            elevationProfile = try? await ElevationService.fetchProfile(
                coordinates: route.geometry.coordinates
            )
            isLoadingElevation = false
        }
    }

    private func selectImportedRoute(_ route: ImportedRoute) {
        clearRoute()
        activeImportedRoute = route
        navigationCoordinates = route.coordinates

        if let elevations = route.elevations {
            elevationProfile = ElevationService.createProfileFromGPX(
                coordinates: route.coordinates,
                elevations: elevations
            )
        }
    }

    private func clearRoute() {
        if isNavigating { stopNavigation() }
        selectedRoute = nil
        activeImportedRoute = nil
        navigationCoordinates = []
        valhallaRoute = nil
        elevationProfile = nil
        focusCoordinate = nil
    }

    // MARK: - Data Loading

    private func loadAllLayers() async {
        loadBundledLayers()
        if auth.isAuthenticated {
            await loadCyclingRoads()
            await loadLocations()
        }
    }

    private func loadBundledLayers() {
        if let url = Bundle.main.url(forResource: "sapporo-osm-cycleways", withExtension: "geojson"),
           let data = try? Data(contentsOf: url) {
            osmCyclewaysData = data
        }
        if let url = Bundle.main.url(forResource: "dosou-osm-bicycle-routes", withExtension: "geojson"),
           let data = try? Data(contentsOf: url) {
            bicycleRoutesData = data
        }
    }

    private func loadCyclingRoads() async {
        do {
            cyclingRoadsData = try await APIClient.shared.fetchData(path: "/api/cycling-roads")
        } catch {}
    }

    private func loadLocations() async {
        do {
            let response = try await APIClient.shared.fetch(LocationsResponse.self, path: "/api/locations")
            savedLocations = response.locations
        } catch {}
    }

    // MARK: - Helpers

    private func goToCurrentLocation() {
        if let loc = locationService.currentLocation {
            applyFocus(loc.coordinate)
        } else {
            locationService.startTracking()
            Task {
                try? await Task.sleep(for: .seconds(1))
                if let loc = locationService.currentLocation {
                    applyFocus(loc.coordinate)
                }
                if !isNavigating && !rideRecorder.isRecording {
                    locationService.stopTracking()
                }
            }
        }
    }

    private func applyFocus(_ coordinate: CLLocationCoordinate2D, zoom: Double? = nil) {
        focusCoordinate = nil
        navZoomLevel = zoom
        DispatchQueue.main.async {
            focusCoordinate = coordinate
        }
    }

    private func formatDuration(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }
}
