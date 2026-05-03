import AudioToolbox
import CoreLocation
import SwiftUI

struct MapScreen: View {
    @Environment(AuthService.self) private var auth

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

    // 位置情報・ナビ
    @State private var locationService = LocationService()
    @State private var isNavigating = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var navigationTimer: Timer?

    // 標高
    @State private var elevationProfile: ElevationProfile?
    @State private var isLoadingElevation = false

    // 地図制御
    @State private var focusCoordinate: CLLocationCoordinate2D?

    // シート表示
    @State private var showRoutes = false
    @State private var showLocations = false
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
                navigationCoordinates: navigationCoordinates,
                locationService: locationService,
                isNavigating: isNavigating
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

                // 走行情報パネル（ナビ中）
                if isNavigating {
                    NavigationInfoPanel(
                        speedKmh: locationService.speedKmh,
                        distanceM: locationService.totalDistanceM,
                        elapsed: elapsedTime,
                        isOffRoute: locationService.isOffRoute
                    )
                    .padding(.horizontal, 8)
                }

                // ルート情報バー
                if let route = selectedRoute {
                    serverRouteInfoBar(route)
                } else if let imported = activeImportedRoute {
                    importedRouteInfoBar(imported)
                }
            }

            // 左上ボタン群
            VStack(spacing: 8) {
                sideButtons
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .sheet(isPresented: $showSettings) {
            SettingsView(onSelectImportedRoute: { route in
                selectImportedRoute(route)
            })
            .environment(auth)
        }
        .task {
            await loadAllLayers()
            setupDeviationFeedback()
        }
    }

    // MARK: - Side Buttons

    private var sideButtons: some View {
        VStack(spacing: 8) {
            // ナビ開始/停止
            if hasActiveRoute {
                if isNavigating {
                    sideButton(icon: "stop.fill", label: "停止") {
                        stopNavigation()
                    }
                } else {
                    sideButton(icon: "play.fill", label: "ナビ") {
                        startNavigation()
                    }
                }
            }

            // サーバ連携（ログイン時のみ）
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

    // MARK: - Navigation

    private func startNavigation() {
        locationService.setRoute(navigationCoordinates)
        locationService.startTracking()
        elapsedTime = 0
        isNavigating = true
        navigationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsedTime += 1
            }
        }
    }

    private func stopNavigation() {
        isNavigating = false
        navigationTimer?.invalidate()
        navigationTimer = nil
        locationService.stopTracking()
        locationService.clearRoute()
    }

    private func setupDeviationFeedback() {
        locationService.onDeviation = {
            // ハプティクス
            let feedback = UIImpactFeedbackGenerator(style: .heavy)
            feedback.impactOccurred()
            // システムサウンド
            AudioServicesPlaySystemSound(1521) // Peek
        }
    }

    // MARK: - Route Selection

    private func selectServerRoute(_ route: SavedRoute) {
        clearRoute()
        selectedRoute = route
        navigationCoordinates = route.coordinates

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

        // GPX 内の標高データがあればチャート表示
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
                if !isNavigating {
                    locationService.stopTracking()
                }
            }
        }
    }

    /// focusCoordinate を一度 nil にリセットしてから設定し直すことで、
    /// 同じ座標でも SwiftUI が変更を検知するようにする
    private func applyFocus(_ coordinate: CLLocationCoordinate2D) {
        focusCoordinate = nil
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
