import CoreLocation
import MapLibre
import SwiftUI

struct RindoMapView: UIViewRepresentable {
    // Layer データ
    var cyclingRoadsData: Data?
    var osmCyclewaysData: Data?
    var bicycleRoutesData: Data?
    var selectedRoute: SavedRoute?
    var savedLocations: [SavedLocation]
    var focusCoordinate: CLLocationCoordinate2D?
    var focusZoomLevel: Double?

    // ナビゲーション
    var navigationCoordinates: [CLLocationCoordinate2D]
    var locationService: LocationService
    var isNavigating: Bool
    // 走行軌跡
    var recordedTrack: [RideRecorder.RecordedTrackPoint]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(forResource: "osm-style", withExtension: "json")!
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 43.0686, longitude: 141.3468),
            zoomLevel: 12,
            animated: false
        )
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        mapView.allowsRotating = false

        // 地点マーカータップ用ジェスチャ
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        for gesture in mapView.gestureRecognizers ?? [] {
            if let existing = gesture as? UITapGestureRecognizer {
                tap.require(toFail: existing)
            }
        }
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            cyclingRoads: cyclingRoadsData,
            osmCycleways: osmCyclewaysData,
            bicycleRoutes: bicycleRoutesData,
            selectedRoute: selectedRoute,
            savedLocations: savedLocations,
            navigationCoordinates: navigationCoordinates,
            currentLocation: locationService.currentLocation,
            course: locationService.course,
            isNavigating: isNavigating,
            recordedTrack: recordedTrack
        )
        if let coord = focusCoordinate {
            let zoom = focusZoomLevel ?? 15
            mapView.setCenter(coord, zoomLevel: zoom, animated: true)
        }

        // ナビ中は現在地を画面下 1/3 に追従表示
        if isNavigating, let loc = locationService.currentLocation {
            let coord = loc.coordinate
            let mapHeight = mapView.frame.height
            // 現在地を画面下 1/3 に配置するため、画面中心を北方向にオフセット
            let offsetY = mapHeight / 6
            let centerPoint = mapView.convert(coord, toPointTo: mapView)
            let adjustedPoint = CGPoint(x: centerPoint.x, y: centerPoint.y - offsetY)
            let adjustedCoord = mapView.convert(adjustedPoint, toCoordinateFrom: mapView)
            mapView.setCenter(adjustedCoord, animated: true)
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, MLNMapViewDelegate {
        private var styleLoaded = false
        private var addedSources: Set<String> = []

        // 保持データ
        private var pendingCyclingRoads: Data?
        private var pendingOSMCycleways: Data?
        private var pendingBicycleRoutes: Data?
        private var currentRoute: SavedRoute?
        private var currentLocations: [SavedLocation] = []
        private var navCoordinates: [CLLocationCoordinate2D] = []
        private var navLocation: CLLocation?
        private var navCourse: Double = 0
        private var navIsActive = false
        private var trackPoints: [RideRecorder.RecordedTrackPoint] = []

        func update(
            mapView: MLNMapView,
            cyclingRoads: Data?,
            osmCycleways: Data?,
            bicycleRoutes: Data?,
            selectedRoute: SavedRoute?,
            savedLocations: [SavedLocation],
            navigationCoordinates: [CLLocationCoordinate2D],
            currentLocation: CLLocation?,
            course: Double,
            isNavigating: Bool,
            recordedTrack: [RideRecorder.RecordedTrackPoint]
        ) {
            pendingCyclingRoads = cyclingRoads
            pendingOSMCycleways = osmCycleways
            pendingBicycleRoutes = bicycleRoutes
            currentRoute = selectedRoute
            currentLocations = savedLocations
            navCoordinates = navigationCoordinates
            trackPoints = recordedTrack
            navLocation = currentLocation
            navCourse = course
            navIsActive = isNavigating
            guard styleLoaded else { return }
            applyAllLayers(to: mapView)
        }

        // MARK: - Tap Handler

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            // MLNAnnotation 経由のタップは使わない
        }

        @objc func handleMapTap(_ sender: UITapGestureRecognizer) {
            guard let mapView = sender.view as? MLNMapView else { return }
            let point = sender.location(in: mapView)

            // 地点マーカーレイヤーをタップ判定
            let features = mapView.visibleFeatures(
                at: point,
                styleLayerIdentifiers: [Self.locationLayerID]
            )
            guard let feature = features.first,
                  let name = feature.attribute(forKey: "name") as? String else {
                // ポップアップ外タップで閉じる
                mapView.deselectAnnotation(mapView.selectedAnnotations.first, animated: true)
                return
            }

            let emoji = feature.attribute(forKey: "emoji") as? String ?? "📍"
            let coordinate = feature.coordinate

            // ポップアップ表示
            let annotation = MLNPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = "\(emoji) \(name)"
            annotation.subtitle = feature.attribute(forKey: "notes") as? String
            mapView.selectAnnotation(annotation, animated: true, completionHandler: nil)
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            true
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleLoaded = true
            // 矢印画像をスタイルに登録
            let arrowImg = ArrowImage.generate()
            style.setImage(arrowImg, forName: "nav-arrow")
            applyAllLayers(to: mapView)
        }

        private func applyAllLayers(to mapView: MLNMapView) {
            guard let style = mapView.style else { return }
            applyLayer1(style: style)
            applyLayer2(style: style)
            applyLayer3(style: style)
            applyRouteLayer(style: style, mapView: mapView)
            applyLocationMarkers(style: style)
            applyTrackLayer(style: style)
            applyNavigationLayers(style: style)
        }

        // MARK: - Layer 1/2/3 (unchanged)

        private func applyLayer1(style: MLNStyle) {
            let id = MapLayerStyle.OSMCycleways.sourceID
            guard let data = pendingOSMCycleways, !addedSources.contains(id) else { return }
            guard let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) else { return }
            let source = MLNShapeSource(identifier: id, shape: shape)
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: MapLayerStyle.OSMCycleways.layerID, source: source)
            layer.lineColor = NSExpression(forConstantValue: MapLayerStyle.OSMCycleways.color)
            layer.lineWidth = NSExpression(forConstantValue: NSNumber(value: Float(MapLayerStyle.OSMCycleways.width)))
            layer.lineOpacity = NSExpression(forConstantValue: NSNumber(value: MapLayerStyle.OSMCycleways.opacity))
            layer.lineJoin = NSExpression(forConstantValue: "round")
            layer.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(layer)
            addedSources.insert(id)
        }

        private func applyLayer2(style: MLNStyle) {
            let id = MapLayerStyle.BicycleRoutes.sourceID
            guard let data = pendingBicycleRoutes, !addedSources.contains(id) else { return }
            guard let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) else { return }
            let source = MLNShapeSource(identifier: id, shape: shape)
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: MapLayerStyle.BicycleRoutes.layerID, source: source)
            layer.lineColor = NSExpression(forConstantValue: MapLayerStyle.BicycleRoutes.color)
            layer.lineWidth = NSExpression(forConstantValue: NSNumber(value: Float(MapLayerStyle.BicycleRoutes.width)))
            layer.lineOpacity = NSExpression(forConstantValue: NSNumber(value: MapLayerStyle.BicycleRoutes.opacity))
            layer.lineJoin = NSExpression(forConstantValue: "round")
            layer.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(layer)
            addedSources.insert(id)
        }

        private func applyLayer3(style: MLNStyle) {
            let id = MapLayerStyle.CuratedRoads.sourceID
            guard let data = pendingCyclingRoads, !addedSources.contains(id) else { return }
            guard let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) else { return }
            let source = MLNShapeSource(identifier: id, shape: shape, options: [
                .simplificationTolerance: 0,
                .maximumZoomLevel: 20,
                .buffer: 512,
            ])
            style.addSource(source)
            // 札幌市公式（large_scale が false または未設定）— オレンジ
            let exclusive = MLNLineStyleLayer(identifier: MapLayerStyle.CuratedRoads.exclusiveLayerID, source: source)
            exclusive.predicate = NSPredicate(format: "road_type == 'exclusive' AND (large_scale == NO OR large_scale == NIL)")
            exclusive.lineColor = NSExpression(forConstantValue: MapLayerStyle.CuratedRoads.color)
            exclusive.lineWidth = NSExpression(forConstantValue: NSNumber(value: Float(MapLayerStyle.CuratedRoads.exclusiveWidth)))
            exclusive.lineJoin = NSExpression(forConstantValue: "round")
            exclusive.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(exclusive)

            let shared = MLNLineStyleLayer(identifier: MapLayerStyle.CuratedRoads.sharedLayerID, source: source)
            shared.predicate = NSPredicate(format: "road_type == 'shared' AND (large_scale == NO OR large_scale == NIL)")
            shared.lineColor = NSExpression(forConstantValue: MapLayerStyle.CuratedRoads.color)
            shared.lineWidth = NSExpression(forConstantValue: NSNumber(value: Float(MapLayerStyle.CuratedRoads.sharedWidth)))
            shared.lineDashPattern = NSExpression(forConstantValue: MapLayerStyle.CuratedRoads.sharedDashPattern)
            shared.lineJoin = NSExpression(forConstantValue: "round")
            shared.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(shared)

            // 北海道大規模自転車道（large_scale == true）— 青紫、太め
            let largeScale = MLNLineStyleLayer(identifier: MapLayerStyle.CuratedRoads.largeScaleLayerID, source: source)
            largeScale.predicate = NSPredicate(format: "large_scale == YES")
            largeScale.lineColor = NSExpression(forConstantValue: MapLayerStyle.CuratedRoads.largeScaleColor)
            largeScale.lineWidth = NSExpression(forConstantValue: NSNumber(value: Float(MapLayerStyle.CuratedRoads.largeScaleWidth)))
            largeScale.lineJoin = NSExpression(forConstantValue: "round")
            largeScale.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(largeScale)

            // 路線名ラベル（Web版と同じ minzoom 10、symbol-spacing 320）
            let label = MLNSymbolStyleLayer(identifier: MapLayerStyle.CuratedRoads.labelLayerID, source: source)
            label.text = NSExpression(forKeyPath: "name")
            label.textColor = NSExpression(forConstantValue: UIColor(red: 0x5C/255, green: 0x2C/255, blue: 0x00/255, alpha: 1))
            label.textHaloColor = NSExpression(forConstantValue: UIColor(white: 1, alpha: 0.95))
            label.textHaloWidth = NSExpression(forConstantValue: NSNumber(value: 1.5))
            label.symbolPlacement = NSExpression(forConstantValue: "line")
            label.symbolSpacing = NSExpression(forConstantValue: NSNumber(value: 320))
            label.textFontSize = NSExpression(forConstantValue: NSNumber(value: 11))
            style.addLayer(label)

            addedSources.insert(id)
        }

        // MARK: - Selected Route (server)

        private static let routeSourceID = "selected-route"
        private static let routeLayerID = "selected-route-line"
        private static let routeHaloLayerID = "selected-route-halo"
        private static let waypointSourceID = "waypoint-markers"
        private static let waypointLayerID = "waypoint-circles"

        private func applyRouteLayer(style: MLNStyle, mapView: MLNMapView) {
            removeLayer(style: style, layerID: Self.routeHaloLayerID)
            removeLayer(style: style, layerID: Self.routeLayerID)
            removeSource(style: style, sourceID: Self.routeSourceID)
            removeLayer(style: style, layerID: Self.waypointLayerID)
            removeSource(style: style, sourceID: Self.waypointSourceID)

            // サーバルートがある場合はそれを表示、なければナビ座標を表示
            let coords: [CLLocationCoordinate2D]
            if let route = currentRoute {
                coords = route.coordinates
            } else if !navCoordinates.isEmpty {
                coords = navCoordinates
            } else {
                return
            }
            guard coords.count >= 2 else { return }

            var mutableCoords = coords
            let polyline = MLNPolyline(coordinates: &mutableCoords, count: UInt(coords.count))
            let routeSource = MLNShapeSource(identifier: Self.routeSourceID, shape: polyline)
            style.addSource(routeSource)

            let halo = MLNLineStyleLayer(identifier: Self.routeHaloLayerID, source: routeSource)
            halo.lineColor = NSExpression(forConstantValue: UIColor.white)
            halo.lineWidth = NSExpression(forConstantValue: NSNumber(value: 8))
            halo.lineJoin = NSExpression(forConstantValue: "round")
            halo.lineCap = NSExpression(forConstantValue: "round")
            halo.lineOpacity = NSExpression(forConstantValue: NSNumber(value: 0.8))
            style.addLayer(halo)

            let line = MLNLineStyleLayer(identifier: Self.routeLayerID, source: routeSource)
            line.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            line.lineWidth = NSExpression(forConstantValue: NSNumber(value: 5))
            line.lineJoin = NSExpression(forConstantValue: "round")
            line.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(line)

            // ウェイポイント（サーバルートのみ）
            if let route = currentRoute {
                let wpFeatures: [MLNPointFeature] = route.waypoints.enumerated().map { index, wp in
                    let f = MLNPointFeature()
                    f.coordinate = wp.coordinate
                    f.attributes = ["index": index]
                    return f
                }
                let wpSource = MLNShapeSource(identifier: Self.waypointSourceID, features: wpFeatures)
                style.addSource(wpSource)
                let wpLayer = MLNCircleStyleLayer(identifier: Self.waypointLayerID, source: wpSource)
                wpLayer.circleRadius = NSExpression(forConstantValue: NSNumber(value: 8))
                wpLayer.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
                wpLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                wpLayer.circleStrokeWidth = NSExpression(forConstantValue: NSNumber(value: 2))
                style.addLayer(wpLayer)
            }

            // カメラフィット
            let bounds = coords.reduce(into: (
                minLat: coords[0].latitude, maxLat: coords[0].latitude,
                minLon: coords[0].longitude, maxLon: coords[0].longitude
            )) { r, c in
                r.minLat = min(r.minLat, c.latitude); r.maxLat = max(r.maxLat, c.latitude)
                r.minLon = min(r.minLon, c.longitude); r.maxLon = max(r.maxLon, c.longitude)
            }
            let bbox = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon),
                ne: CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon)
            )
            let camera = mapView.cameraThatFitsCoordinateBounds(
                bbox, edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 200, right: 40)
            )
            mapView.setCamera(camera, animated: true)
        }

        // MARK: - Location Markers

        private static let locationSourceID = "saved-locations"
        private static let locationLayerID = "saved-locations-circles"
        private static let locationLabelLayerID = "saved-locations-labels"

        private func applyLocationMarkers(style: MLNStyle) {
            removeLayer(style: style, layerID: Self.locationLabelLayerID)
            removeLayer(style: style, layerID: Self.locationLayerID)
            removeSource(style: style, sourceID: Self.locationSourceID)
            guard !currentLocations.isEmpty else { return }
            let features: [MLNPointFeature] = currentLocations.map { loc in
                let f = MLNPointFeature()
                f.coordinate = loc.coordinate
                f.attributes = ["name": loc.name, "category": loc.category.rawValue, "emoji": loc.category.emoji]
                return f
            }
            let source = MLNShapeSource(identifier: Self.locationSourceID, features: features)
            style.addSource(source)
            let circle = MLNCircleStyleLayer(identifier: Self.locationLayerID, source: source)
            circle.circleRadius = NSExpression(forConstantValue: NSNumber(value: 12))
            circle.circleColor = NSExpression(forConstantValue: UIColor.systemOrange)
            circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            circle.circleStrokeWidth = NSExpression(forConstantValue: NSNumber(value: 2))
            circle.circleOpacity = NSExpression(forConstantValue: NSNumber(value: 0.9))
            style.addLayer(circle)
            let label = MLNSymbolStyleLayer(identifier: Self.locationLabelLayerID, source: source)
            label.text = NSExpression(forKeyPath: "emoji")
            label.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -1.8)))
            label.textAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(label)
        }

        // MARK: - Recorded Track (breadcrumb trail)

        private static let trackSourceID = "recorded-track"
        private static let trackLayerID = "recorded-track-line"

        private func applyTrackLayer(style: MLNStyle) {
            removeLayer(style: style, layerID: Self.trackLayerID)
            removeSource(style: style, sourceID: Self.trackSourceID)

            guard trackPoints.count >= 2 else { return }

            var coords = trackPoints.map(\.coordinate)
            let polyline = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
            let source = MLNShapeSource(identifier: Self.trackSourceID, shape: polyline)
            style.addSource(source)

            let layer = MLNLineStyleLayer(identifier: Self.trackLayerID, source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
            layer.lineWidth = NSExpression(forConstantValue: NSNumber(value: 3))
            layer.lineJoin = NSExpression(forConstantValue: "round")
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineOpacity = NSExpression(forConstantValue: NSNumber(value: 0.8))
            style.addLayer(layer)
        }

        // MARK: - Navigation Layers (arrow + destination line)

        private static let arrowSourceID = "nav-arrow"
        private static let arrowLayerID = "nav-arrow-layer"
        private static let destLineSourceID = "nav-dest-line"
        private static let destLineLayerID = "nav-dest-line-layer"

        private func applyNavigationLayers(style: MLNStyle) {
            removeLayer(style: style, layerID: Self.arrowLayerID)
            removeSource(style: style, sourceID: Self.arrowSourceID)
            removeLayer(style: style, layerID: Self.destLineLayerID)
            removeSource(style: style, sourceID: Self.destLineSourceID)

            guard navIsActive, let loc = navLocation else { return }
            let current = loc.coordinate

            // 矢印マーカー（進行方向に回転）
            let arrowFeature = MLNPointFeature()
            arrowFeature.coordinate = current
            arrowFeature.attributes = ["course": navCourse]
            let arrowSource = MLNShapeSource(identifier: Self.arrowSourceID, features: [arrowFeature])
            style.addSource(arrowSource)

            let arrowLayer = MLNSymbolStyleLayer(identifier: Self.arrowLayerID, source: arrowSource)
            arrowLayer.iconImageName = NSExpression(forConstantValue: "nav-arrow")
            arrowLayer.iconRotation = NSExpression(forKeyPath: "course")
            arrowLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            arrowLayer.iconAnchor = NSExpression(forConstantValue: "center")
            style.addLayer(arrowLayer)

            // 目的地への直線
            if let destination = navCoordinates.last {
                var lineCoords = [current, destination]
                let polyline = MLNPolyline(coordinates: &lineCoords, count: 2)
                let lineSource = MLNShapeSource(identifier: Self.destLineSourceID, shape: polyline)
                style.addSource(lineSource)

                let lineLayer = MLNLineStyleLayer(identifier: Self.destLineLayerID, source: lineSource)
                lineLayer.lineColor = NSExpression(forConstantValue: UIColor.systemGray)
                lineLayer.lineWidth = NSExpression(forConstantValue: NSNumber(value: 1.5))
                lineLayer.lineDashPattern = NSExpression(forConstantValue: [6, 4])
                lineLayer.lineOpacity = NSExpression(forConstantValue: NSNumber(value: 0.6))
                style.addLayer(lineLayer)
            }
        }

        // MARK: - Helpers

        private func removeLayer(style: MLNStyle, layerID: String) {
            if let l = style.layer(withIdentifier: layerID) { style.removeLayer(l) }
        }
        private func removeSource(style: MLNStyle, sourceID: String) {
            if let s = style.source(withIdentifier: sourceID) { style.removeSource(s) }
        }
    }
}
