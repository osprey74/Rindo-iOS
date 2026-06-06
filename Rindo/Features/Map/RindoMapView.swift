import CoreLocation
import MapLibre
import SwiftUI

struct RindoMapView: UIViewRepresentable {
    var selectedRoute: SavedRoute?
    var savedLocations: [SavedLocation]
    var focusCoordinate: CLLocationCoordinate2D?
    var focusZoomLevel: Double?

    // ナビゲーション
    var navigationCoordinates: [CLLocationCoordinate2D]
    var locationService: LocationService
    var isNavigating: Bool
    var nextManeuverCoordinate: CLLocationCoordinate2D?
    // 走行軌跡
    var recordedTrack: [RideRecorder.RecordedTrackPoint]

    // キュレーションサイクリングロード
    var cyclingRoads: [CyclingRoadFeature] = []
    var onCyclingRoadTapped: ((CyclingRoadFeature) -> Void)?
    var onLocationTapped: ((SavedLocation) -> Void)?

    // 目的地設定（ロングプレス）
    var destinationCoordinate: CLLocationCoordinate2D?
    var onDestinationSet: ((CLLocationCoordinate2D) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCyclingRoadTapped: onCyclingRoadTapped,
            onLocationTapped: onLocationTapped,
            onDestinationSet: onDestinationSet
        )
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
        mapView.allowsTilting = false

        // ロングプレスで目的地を設定
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onCyclingRoadTapped = onCyclingRoadTapped
        context.coordinator.onLocationTapped = onLocationTapped
        context.coordinator.onDestinationSet = onDestinationSet
        context.coordinator.updateDestinationPin(mapView: mapView, coordinate: destinationCoordinate)
        context.coordinator.update(
            mapView: mapView,
            selectedRoute: selectedRoute,
            savedLocations: savedLocations,
            navigationCoordinates: navigationCoordinates,
            currentLocation: locationService.currentLocation,
            course: locationService.course,
            isNavigating: isNavigating,
            recordedTrack: recordedTrack,
            cyclingRoads: cyclingRoads,
            nextManeuverCoordinate: nextManeuverCoordinate
        )
        if let coord = focusCoordinate {
            let zoom = focusZoomLevel ?? 15
            mapView.setCenter(coord, zoomLevel: zoom, animated: true)
        }

        // ナビ中は現在地を画面下 1/3 に追従表示 + ヘッドアップ
        if isNavigating, let loc = locationService.currentLocation {
            let course = locationService.course
            // ヘッドアップ: 進行方向を上にする（course が有効な場合のみ）
            if course >= 0 {
                mapView.direction = course
            }

            let coord = loc.coordinate
            let mapHeight = mapView.frame.height
            // 現在地を画面下 1/3 に配置するため、画面中心を進行方向前方にオフセット
            let offsetY = mapHeight / 6
            let centerPoint = mapView.convert(coord, toPointTo: mapView)
            let adjustedPoint = CGPoint(x: centerPoint.x, y: centerPoint.y - offsetY)
            let adjustedCoord = mapView.convert(adjustedPoint, toCoordinateFrom: mapView)
            mapView.setCenter(adjustedCoord, animated: true)
        } else {
            // ナビ終了時はノースアップに戻す
            if mapView.direction != 0 {
                mapView.direction = 0
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, MLNMapViewDelegate {
        private var styleLoaded = false
        private var addedSources: Set<String> = []

        private var currentRoute: SavedRoute?
        private var currentLocations: [SavedLocation] = []
        private var navCoordinates: [CLLocationCoordinate2D] = []
        private var navLocation: CLLocation?
        private var navCourse: Double = 0
        private var navIsActive = false
        private var trackPoints: [RideRecorder.RecordedTrackPoint] = []
        private var nextManeuverCoord: CLLocationCoordinate2D?

        // 地点マーカー（アノテーション方式）
        private var locationAnnotations: [MLNPointAnnotation] = []
        private var annotationToLocation: [ObjectIdentifier: SavedLocation] = [:]

        // キュレーションサイクリングロード（アノテーション方式 — タイル変換を迂回）
        private var cyclingRoadAnnotations: [MLNPolyline] = []
        private var cyclingRoadLabelAnnotations: [MLNPointAnnotation] = []
        private var annotationToRoad: [ObjectIdentifier: CyclingRoadFeature] = [:]
        private var cyclingRoadFeatures: [CyclingRoadFeature] = []
        var onCyclingRoadTapped: ((CyclingRoadFeature) -> Void)?
        var onLocationTapped: ((SavedLocation) -> Void)?
        var onDestinationSet: ((CLLocationCoordinate2D) -> Void)?

        // 目的地ピン
        private var destinationAnnotation: MLNPointAnnotation?

        init(
            onCyclingRoadTapped: ((CyclingRoadFeature) -> Void)? = nil,
            onLocationTapped: ((SavedLocation) -> Void)? = nil,
            onDestinationSet: ((CLLocationCoordinate2D) -> Void)? = nil
        ) {
            self.onCyclingRoadTapped = onCyclingRoadTapped
            self.onLocationTapped = onLocationTapped
            self.onDestinationSet = onDestinationSet
            super.init()
        }

        // MARK: - Long Press → Destination

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            onDestinationSet?(coordinate)
        }

        func updateDestinationPin(mapView: MLNMapView, coordinate: CLLocationCoordinate2D?) {
            // 既存ピンを除去
            if let existing = destinationAnnotation {
                mapView.removeAnnotation(existing)
                destinationAnnotation = nil
            }

            guard let coord = coordinate else { return }

            let pin = MLNPointAnnotation()
            pin.coordinate = coord
            pin.title = "🏁 目的地"
            mapView.addAnnotation(pin)
            destinationAnnotation = pin
        }

        func update(
            mapView: MLNMapView,
            selectedRoute: SavedRoute?,
            savedLocations: [SavedLocation],
            navigationCoordinates: [CLLocationCoordinate2D],
            currentLocation: CLLocation?,
            course: Double,
            isNavigating: Bool,
            recordedTrack: [RideRecorder.RecordedTrackPoint],
            cyclingRoads: [CyclingRoadFeature],
            nextManeuverCoordinate: CLLocationCoordinate2D?
        ) {
            currentRoute = selectedRoute
            currentLocations = savedLocations
            navCoordinates = navigationCoordinates
            trackPoints = recordedTrack
            navLocation = currentLocation
            navCourse = course
            navIsActive = isNavigating
            nextManeuverCoord = nextManeuverCoordinate
            // サイクリングロードアノテーションの追加（初回のみ）
            if cyclingRoads.count != cyclingRoadFeatures.count {
                cyclingRoadFeatures = cyclingRoads
                applyCuratedRoadAnnotations(to: mapView)
            }

            // 地点マーカー（アノテーション方式、スタイル不要）
            applyLocationMarkers(to: mapView)

            guard styleLoaded else { return }
            applyAllLayers(to: mapView)
        }

        // MARK: - Tap Handler

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            // サイクリングロードアノテーションのタップ
            if let polyline = annotation as? MLNPolyline,
               let road = annotationToRoad[ObjectIdentifier(polyline)] {
                onCyclingRoadTapped?(road)
                mapView.deselectAnnotation(annotation, animated: false)
                return
            }

            // 地点アノテーションのタップ
            if let point = annotation as? MLNPointAnnotation,
               let location = annotationToLocation[ObjectIdentifier(point)] {
                onLocationTapped?(location)
                mapView.deselectAnnotation(annotation, animated: false)
            }
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            false
        }

        // MARK: - Annotation Styling

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if let polyline = annotation as? MLNPolyline,
               let road = annotationToRoad[ObjectIdentifier(polyline)],
               road.properties.isLargeScale {
                return MapLayerStyle.CuratedRoads.largeScaleColor
            }
            return MapLayerStyle.CuratedRoads.color
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            if let road = annotationToRoad[ObjectIdentifier(annotation)],
               road.properties.isLargeScale {
                return MapLayerStyle.CuratedRoads.largeScaleWidth
            }
            return MapLayerStyle.CuratedRoads.exclusiveWidth
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
            applyRouteLayer(style: style, mapView: mapView)
            applyTrackLayer(style: style)
            applyNavigationLayers(style: style)
            applyNextManeuverPin(style: style)
        }

        // MARK: - Curated Cycling Roads (Annotation-based)

        /// MLNPolyline + ラベル用 MLNPointAnnotation を追加
        private func applyCuratedRoadAnnotations(to mapView: MLNMapView) {
            // 既存アノテーションを除去
            if !cyclingRoadAnnotations.isEmpty {
                mapView.removeAnnotations(cyclingRoadAnnotations)
                cyclingRoadAnnotations.removeAll()
                annotationToRoad.removeAll()
            }
            if !cyclingRoadLabelAnnotations.isEmpty {
                mapView.removeAnnotations(cyclingRoadLabelAnnotations)
                cyclingRoadLabelAnnotations.removeAll()
            }

            guard !cyclingRoadFeatures.isEmpty else { return }

            for road in cyclingRoadFeatures {
                var coords = road.coordinates
                guard coords.count >= 2 else { continue }

                // ルートライン
                let polyline = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
                cyclingRoadAnnotations.append(polyline)
                annotationToRoad[ObjectIdentifier(polyline)] = road

                // ラベル（長いルートは複数配置）
                let labelPositions: [Int]
                if coords.count > 200 {
                    labelPositions = [coords.count / 4, coords.count / 2, coords.count * 3 / 4]
                } else {
                    labelPositions = [coords.count / 2]
                }
                for pos in labelPositions {
                    let label = MLNPointAnnotation()
                    label.coordinate = coords[pos]
                    label.title = road.properties.name
                    cyclingRoadLabelAnnotations.append(label)
                }
            }

            mapView.addAnnotations(cyclingRoadAnnotations)
            mapView.addAnnotations(cyclingRoadLabelAnnotations)
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let pointAnnotation = annotation as? MLNPointAnnotation else {
                return nil
            }

            // 目的地ピン（ロングプレスで設定）
            if pointAnnotation === destinationAnnotation {
                let size: CGFloat = 40
                let reuseID = "destination-pin"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                if view == nil {
                    view = MLNAnnotationView(reuseIdentifier: reuseID)
                    view!.frame = CGRect(x: 0, y: 0, width: size, height: size)
                    view!.centerOffset = CGVector(dx: 0, dy: -size / 2)
                }
                view!.subviews.forEach { $0.removeFromSuperview() }

                let bg = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
                bg.backgroundColor = .systemRed
                bg.layer.cornerRadius = size / 2
                bg.layer.borderColor = UIColor.white.cgColor
                bg.layer.borderWidth = 3
                bg.layer.shadowColor = UIColor.black.cgColor
                bg.layer.shadowOffset = CGSize(width: 0, height: 3)
                bg.layer.shadowRadius = 4
                bg.layer.shadowOpacity = 0.4

                let icon = UIImageView(frame: bg.bounds.insetBy(dx: 8, dy: 8))
                icon.image = UIImage(systemName: "flag.fill")
                icon.tintColor = .white
                icon.contentMode = .scaleAspectFit
                bg.addSubview(icon)

                view!.addSubview(bg)
                return view
            }

            // 地点マーカー（カテゴリ別 emoji アイコン）
            if let location = annotationToLocation[ObjectIdentifier(pointAnnotation)] {
                let size: CGFloat = 36
                let reuseID = "location-\(location.category.rawValue)"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                if view == nil {
                    view = MLNAnnotationView(reuseIdentifier: reuseID)
                    view!.frame = CGRect(x: 0, y: 0, width: size, height: size)
                    view!.centerOffset = CGVector(dx: 0, dy: 0)
                }
                view!.subviews.forEach { $0.removeFromSuperview() }

                let bg = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
                bg.backgroundColor = location.category.markerUIColor
                bg.layer.cornerRadius = size / 2
                bg.layer.borderColor = UIColor.white.cgColor
                bg.layer.borderWidth = 2.5
                bg.layer.shadowColor = UIColor.black.cgColor
                bg.layer.shadowOffset = CGSize(width: 0, height: 2)
                bg.layer.shadowRadius = 3
                bg.layer.shadowOpacity = 0.3

                let emoji = UILabel(frame: bg.bounds)
                emoji.text = location.category.emoji
                emoji.font = .systemFont(ofSize: 20)
                emoji.textAlignment = .center
                bg.addSubview(emoji)

                view!.addSubview(bg)
                view!.isEnabled = true
                return view
            }

            // サイクリングロードラベル
            if cyclingRoadLabelAnnotations.contains(pointAnnotation) {
                let reuseID = "cycling-road-label"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                if view == nil {
                    view = MLNAnnotationView(reuseIdentifier: reuseID)
                    view!.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
                view!.subviews.forEach { $0.removeFromSuperview() }

                let label = UILabel()
                label.text = pointAnnotation.title ?? ""
                label.font = .systemFont(ofSize: 11, weight: .medium)
                label.textColor = .label
                label.backgroundColor = UIColor.white.withAlphaComponent(0.5)
                label.layer.cornerRadius = 3
                label.clipsToBounds = true
                label.textAlignment = .center
                let insetPadding = UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)
                label.sizeToFit()
                label.frame = label.frame.inset(by: UIEdgeInsets(
                    top: -insetPadding.top, left: -insetPadding.left,
                    bottom: -insetPadding.bottom, right: -insetPadding.right
                ))
                label.center = CGPoint(x: 0, y: -10)
                view!.addSubview(label)
                return view
            }

            return nil
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

        // MARK: - Location Markers (Annotation-based)

        private static let locationLayerID = "saved-locations-circles"

        private func applyLocationMarkers(to mapView: MLNMapView) {
            // 変更がなければスキップ
            let currentIds = Set(currentLocations.map(\.id))
            let existingIds = Set(annotationToLocation.values.map(\.id))
            guard currentIds != existingIds else { return }

            // 既存アノテーションを除去
            if !locationAnnotations.isEmpty {
                mapView.removeAnnotations(locationAnnotations)
                locationAnnotations.removeAll()
                annotationToLocation.removeAll()
            }

            guard !currentLocations.isEmpty else { return }

            for loc in currentLocations {
                let pin = MLNPointAnnotation()
                pin.coordinate = loc.coordinate
                pin.title = "\(loc.category.emoji) \(loc.name)"
                pin.subtitle = loc.notes
                locationAnnotations.append(pin)
                annotationToLocation[ObjectIdentifier(pin)] = loc
            }

            mapView.addAnnotations(locationAnnotations)
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

        // MARK: - Next Maneuver Pin (次の曲がり角マーカー)

        private static let maneuverPinSourceID = "next-maneuver-pin"
        private static let maneuverPinLayerID = "next-maneuver-pin-circle"
        private static let maneuverPinPulseLayerID = "next-maneuver-pin-pulse"

        private func applyNextManeuverPin(style: MLNStyle) {
            removeLayer(style: style, layerID: Self.maneuverPinPulseLayerID)
            removeLayer(style: style, layerID: Self.maneuverPinLayerID)
            removeSource(style: style, sourceID: Self.maneuverPinSourceID)

            guard navIsActive, let coord = nextManeuverCoord else { return }

            let feature = MLNPointFeature()
            feature.coordinate = coord
            let source = MLNShapeSource(identifier: Self.maneuverPinSourceID, features: [feature])
            style.addSource(source)

            // 外側パルス（大きめの半透明サークル）
            let pulse = MLNCircleStyleLayer(identifier: Self.maneuverPinPulseLayerID, source: source)
            pulse.circleRadius = NSExpression(forConstantValue: NSNumber(value: 18))
            pulse.circleColor = NSExpression(forConstantValue: UIColor.systemGreen)
            pulse.circleOpacity = NSExpression(forConstantValue: NSNumber(value: 0.3))
            style.addLayer(pulse)

            // 内側ピン
            let pin = MLNCircleStyleLayer(identifier: Self.maneuverPinLayerID, source: source)
            pin.circleRadius = NSExpression(forConstantValue: NSNumber(value: 10))
            pin.circleColor = NSExpression(forConstantValue: UIColor.systemGreen)
            pin.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            pin.circleStrokeWidth = NSExpression(forConstantValue: NSNumber(value: 3))
            style.addLayer(pin)
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
