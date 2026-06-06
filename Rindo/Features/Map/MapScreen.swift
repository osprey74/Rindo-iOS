import AudioToolbox
import CoreLocation
import SwiftUI

struct MapScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var modelContext

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

    // 走行モード
    @AppStorage("rideMode") private var rideModeRaw = RideMode.leisure.rawValue
    private var rideMode: RideMode { RideMode(rawValue: rideModeRaw) ?? .leisure }

    // オフラインマップ
    @State private var offlineMapManager = OfflineMapManager()

    // リマインダー
    @State private var reminderManager = ReminderManager()
    @AppStorage("breakIntervalMinutes") private var breakIntervalMinutes = 60
    @AppStorage("refuelIntervalKm") private var refuelIntervalKm = 50.0

    // 地点ポップオーバー
    @State private var selectedLocation: SavedLocation?

    // サイクリングロード
    @State private var cyclingRoads: [CyclingRoadFeature] = []
    @State private var selectedCyclingRoad: CyclingRoadFeature?
    @State private var cyclingRoadElevation: ElevationProfile?
    @State private var isLoadingCyclingRoadElevation = false

    // 目的地（ロングプレスで設定）
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var isLoadingRoute = false

    // ルーティングモード設定
    @AppStorage("routingMode") private var routingMode = "apple"
    @AppStorage("valhallaServerURL") private var valhallaServerURL = ""

    // エラー
    @State private var errorMessage: String?

    /// 現在のルーティング設定に基づくプロバイダを返す
    private var routeProvider: any RouteProvider {
        if routingMode == "valhalla",
           !valhallaServerURL.isEmpty,
           let url = URL(string: valhallaServerURL) {
            return ValhallaRouteProvider(baseURL: url)
        }
        return AppleRouteProvider()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 地図
            RindoMapView(
                selectedRoute: selectedRoute,
                savedLocations: savedLocations,
                focusCoordinate: focusCoordinate,
                focusZoomLevel: navZoomLevel,
                navigationCoordinates: navigationCoordinates,
                locationService: locationService,
                isNavigating: isNavigating,
                nextManeuverCoordinate: navManager.currentManeuver?.coordinate,
                recordedTrack: rideRecorder.isRecording ? rideRecorder.trackPoints : [],
                cyclingRoads: cyclingRoads,
                onCyclingRoadTapped: { road in selectCyclingRoad(road) },
                onLocationTapped: { location in
                    selectedLocation = location
                    applyFocus(location.coordinate)
                },
                destinationCoordinate: destinationCoordinate,
                onDestinationSet: { coord in setDestination(coord) }
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

                // 地点ポップオーバー
                if let location = selectedLocation {
                    LocationPopover(location: location) {
                        withAnimation { selectedLocation = nil }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ルート情報バー（ナビ中は非表示）
                if !isNavigating {
                    if let route = selectedRoute {
                        serverRouteInfoBar(route)
                    } else if let imported = activeImportedRoute {
                        importedRouteInfoBar(imported)
                    } else if destinationCoordinate != nil {
                        destinationInfoBar()
                    } else if let road = selectedCyclingRoad {
                        CyclingRoadDetailCard(
                            road: road,
                            elevationProfile: cyclingRoadElevation,
                            isLoadingElevation: isLoadingCyclingRoadElevation,
                            onStartNavigation: { startCyclingRoadNavigation(road) },
                            onDismiss: { dismissCyclingRoad() }
                        )
                    }
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
            SettingsView(
                offlineMapManager: offlineMapManager,
                homeCoordinate: savedLocations.first(where: { $0.category == .home })?.coordinate,
                onSelectImportedRoute: { route in
                selectImportedRoute(route)
            })
            .environment(auth)
        }
        .task {
            // セッション復元を待ってから読み込み（トークンが APIClient にセットされた後）
            await auth.restoreSession()
            await loadAllLayers()
            setupDeviationFeedback()
            setupNavLocationUpdates()
        }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth {
                Task { await loadLocations() }
            } else {
                savedLocations = []
            }
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
        selectedRoute != nil || activeImportedRoute != nil || (destinationCoordinate != nil && valhallaRoute != nil)
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

        // HealthKit から体重取得
        Task {
            if await HealthKitService.shared.requestAuthorization() {
                if let weight = await HealthKitService.shared.fetchBodyMass() {
                    rideRecorder.weightKg = weight
                }
            }
        }

        // リマインダー設定
        if rideMode.remindersEnabled {
            reminderManager.breakIntervalMinutes = breakIntervalMinutes
            reminderManager.refuelIntervalKm = refuelIntervalKm
        } else {
            reminderManager.breakIntervalMinutes = 0
            reminderManager.refuelIntervalKm = 0
        }
        reminderManager.voiceGuide = navManager.voiceGuide
        rideRecorder.reminderManager = reminderManager

        rideRecorder.start()
        if !locationService.isTracking {
            locationService.startTracking()
        }
    }

    private func stopRideRecording() {
        guard let summary = rideRecorder.stop() else { return }
        rideRecorder.reminderManager = nil
        locationService.rideRecorder = nil
        if !isNavigating {
            locationService.stopTracking()
        }

        // SwiftData に保存
        let rideLog = RideLog(summary: summary)
        modelContext.insert(rideLog)

        // HealthKit ワークアウト書き戻し
        Task {
            await HealthKitService.shared.saveWorkout(
                startDate: summary.startedAt,
                endDate: summary.endedAt,
                distanceKm: summary.distanceKm,
                caloriesKcal: summary.caloriesKcal
            )
        }

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
        UIApplication.shared.isIdleTimerDisabled = true

        // 走行モードの音声トリガ距離を適用
        navManager.voiceTriggerDistances = rideMode.voiceTriggerDistances

        // ターンバイターンナビを開始（RouteProvider 取得済みルート）
        if let vRoute = valhallaRoute {
            let waypoints: [CLLocationCoordinate2D]
            if let serverRoute = selectedRoute {
                waypoints = serverRoute.waypoints.map(\.coordinate)
            } else if let dest = destinationCoordinate, let loc = locationService.currentLocation {
                waypoints = [loc.coordinate, dest]
            } else {
                waypoints = navigationCoordinates
            }
            navManager.start(route: vRoute, waypoints: waypoints)
        }

        // ナビ開始時に現在地付近をズームイン
        if let loc = locationService.currentLocation {
            applyFocus(loc.coordinate, zoom: rideMode.navZoomLevel)
        }
    }

    private func stopNavigation() {
        isNavigating = false
        showSimpleNav = false
        navManager.stop()
        locationService.clearRoute()
        UIApplication.shared.isIdleTimerDisabled = false
        if !rideRecorder.isRecording {
            locationService.stopTracking()
        }

        // ルート選択状態をクリア（他のルートをタップ可能にする）
        selectedRoute = nil
        activeImportedRoute = nil
        destinationCoordinate = nil
        navigationCoordinates = []
        valhallaRoute = nil
        elevationProfile = nil
        focusCoordinate = nil
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
            let provider = routeProvider
            let newRoute = try await provider.fetchRoute(
                from: request.from,
                to: request.to
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

        // ルートプロバイダでターンバイターンルートを取得
        Task {
            do {
                let provider = routeProvider
                valhallaRoute = try await provider.fetchRoute(
                    waypoints: route.waypoints.map(\.coordinate)
                )
                if let vRoute = valhallaRoute {
                    navigationCoordinates = vRoute.coordinates
                }
            } catch {
                valhallaRoute = nil
                errorMessage = "ルート取得失敗: \(error.localizedDescription)"
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
        destinationCoordinate = nil
        navigationCoordinates = []
        valhallaRoute = nil
        elevationProfile = nil
        focusCoordinate = nil
    }

    // MARK: - Data Loading

    private func loadAllLayers() async {
        // サイクリングロードは認証不要（公開API）
        await loadCyclingRoads()

        if auth.isAuthenticated {
            await loadLocations()
        }
    }

    private func loadCyclingRoads() async {
        guard let url = Bundle.main.url(forResource: "sapporo-cyclingroad.corrected", withExtension: "geojson") else {
            errorMessage = "サイクリングロード: バンドルファイルが見つかりません"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let response = try decoder.decode(CyclingRoadsResponse.self, from: data)
            cyclingRoads = response.features
        } catch {
            errorMessage = "サイクリングロード: \(error.localizedDescription)"
        }
    }

    private func loadLocations() async {
        do {
            let response = try await APIClient.shared.fetch(LocationsResponse.self, path: "/api/locations")
            savedLocations = response.locations
        } catch {}
    }

    // MARK: - Cycling Road Selection

    private func selectCyclingRoad(_ road: CyclingRoadFeature) {
        // 既存ルートがあれば閉じない（サイクリングロードカードのみ切替）
        if selectedRoute != nil || activeImportedRoute != nil { return }

        withAnimation {
            selectedCyclingRoad = road
            cyclingRoadElevation = nil
        }

        // 標高プロファイルを非同期取得
        Task {
            isLoadingCyclingRoadElevation = true
            cyclingRoadElevation = try? await ElevationService.fetchProfile(
                coordinates: road.coordinatePairs
            )
            isLoadingCyclingRoadElevation = false
        }
    }

    private func dismissCyclingRoad() {
        withAnimation {
            selectedCyclingRoad = nil
            cyclingRoadElevation = nil
            isLoadingCyclingRoadElevation = false
        }
    }

    /// サイクリングロードからナビを開始
    private func startCyclingRoadNavigation(_ road: CyclingRoadFeature) {
        let coords = road.coordinates
        guard coords.count >= 2 else { return }

        clearRoute()
        navigationCoordinates = coords
        selectedCyclingRoad = nil
        cyclingRoadElevation = nil

        let start = coords.first!
        let end = coords.last!
        Task {
            do {
                let provider = routeProvider
                valhallaRoute = try await provider.fetchRoute(from: start, to: end)
                if let vRoute = valhallaRoute {
                    navigationCoordinates = vRoute.coordinates
                }
            } catch {
                valhallaRoute = nil
            }
            startNavigation()
        }
    }

    // MARK: - Destination (standalone navigation)

    /// ロングプレスで目的地を設定し、現在地からのルートを取得
    private func setDestination(_ coordinate: CLLocationCoordinate2D) {
        // ナビ中は目的地設定を無視
        guard !isNavigating else { return }

        clearRoute()
        destinationCoordinate = coordinate
        applyFocus(coordinate)

        // 現在地が取得できればルート計算開始
        if let currentLoc = locationService.currentLocation {
            fetchRouteToDestination(from: currentLoc.coordinate, to: coordinate)
        } else {
            // 位置情報を取得してからルート計算
            locationService.startTracking()
            Task {
                try? await Task.sleep(for: .seconds(2))
                if let loc = locationService.currentLocation {
                    fetchRouteToDestination(from: loc.coordinate, to: coordinate)
                } else {
                    errorMessage = "現在地を取得できません"
                }
            }
        }
    }

    private func fetchRouteToDestination(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        isLoadingRoute = true
        Task {
            do {
                let provider = routeProvider
                let route = try await provider.fetchRoute(from: from, to: to)
                valhallaRoute = route
                navigationCoordinates = route.coordinates
            } catch {
                errorMessage = "ルート取得失敗: \(error.localizedDescription)"
                valhallaRoute = nil
            }
            isLoadingRoute = false
        }
    }

    private func destinationInfoBar() -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("目的地").font(.headline)
                    if isLoadingRoute {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("ルート計算中...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let route = valhallaRoute {
                        HStack(spacing: 12) {
                            Text(String(format: "%.1f km", route.totalDistanceKm))
                            Text(formatDuration(route.totalTimeSeconds / 60))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if valhallaRoute != nil {
                    Button {
                        startNavigation()
                    } label: {
                        Label("ナビ開始", systemImage: "location.north.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.blue, in: Capsule())
                    }
                }
                Button { withAnimation { clearRoute() } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
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
