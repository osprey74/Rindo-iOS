import MapLibre
import SwiftUI

struct RindoMapView: UIViewRepresentable {
    /// Layer 3: API から取得した GeoJSON Data
    var cyclingRoadsData: Data?
    /// Layer 1: バンドル済み OSM cycleway GeoJSON Data
    var osmCyclewaysData: Data?
    /// Layer 2: バンドル済み OSM bicycle routes GeoJSON Data
    var bicycleRoutesData: Data?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(forResource: "osm-style", withExtension: "json")!
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)

        // 札幌中心
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 43.0686, longitude: 141.3468),
            zoomLevel: 12,
            animated: false
        )

        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator

        // ピンチ回転を無効化（サイクリング中は北固定が自然）
        mapView.allowsRotating = false

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            cyclingRoads: cyclingRoadsData,
            osmCycleways: osmCyclewaysData,
            bicycleRoutes: bicycleRoutesData
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MLNMapViewDelegate {
        private var styleLoaded = false
        private var pendingCyclingRoads: Data?
        private var pendingOSMCycleways: Data?
        private var pendingBicycleRoutes: Data?
        private var addedSources: Set<String> = []

        func update(
            mapView: MLNMapView,
            cyclingRoads: Data?,
            osmCycleways: Data?,
            bicycleRoutes: Data?
        ) {
            pendingCyclingRoads = cyclingRoads
            pendingOSMCycleways = osmCycleways
            pendingBicycleRoutes = bicycleRoutes
            guard styleLoaded else { return }
            applyAllLayers(to: mapView)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleLoaded = true
            applyAllLayers(to: mapView)
        }

        // MARK: - Layer Application

        private func applyAllLayers(to mapView: MLNMapView) {
            guard let style = mapView.style else { return }
            applyLayer1(style: style)
            applyLayer2(style: style)
            applyLayer3(style: style)
        }

        /// Layer 1: OSM Cycleways（緑、幅 3）
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

        /// Layer 2: OSM Bicycle Routes（青、幅 4）
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

        /// Layer 3: Curated Cycling Roads（オレンジ、専用実線/共用破線）
        private func applyLayer3(style: MLNStyle) {
            let id = MapLayerStyle.CuratedRoads.sourceID
            guard let data = pendingCyclingRoads, !addedSources.contains(id) else { return }
            guard let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) else { return }

            let source = MLNShapeSource(identifier: id, shape: shape)
            style.addSource(source)

            // 専用（exclusive）: オレンジ実線、幅 4
            let exclusive = MLNLineStyleLayer(
                identifier: MapLayerStyle.CuratedRoads.exclusiveLayerID,
                source: source
            )
            exclusive.predicate = NSPredicate(format: "road_type == 'exclusive'")
            exclusive.lineColor = NSExpression(forConstantValue: MapLayerStyle.CuratedRoads.color)
            exclusive.lineWidth = NSExpression(forConstantValue: NSNumber(value: Float(MapLayerStyle.CuratedRoads.exclusiveWidth)))
            exclusive.lineJoin = NSExpression(forConstantValue: "round")
            exclusive.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(exclusive)

            // 共用（shared）: オレンジ破線、幅 2
            let shared = MLNLineStyleLayer(
                identifier: MapLayerStyle.CuratedRoads.sharedLayerID,
                source: source
            )
            shared.predicate = NSPredicate(format: "road_type == 'shared'")
            shared.lineColor = NSExpression(forConstantValue: MapLayerStyle.CuratedRoads.color)
            shared.lineWidth = NSExpression(forConstantValue: NSNumber(value: Float(MapLayerStyle.CuratedRoads.sharedWidth)))
            shared.lineDashPattern = NSExpression(forConstantValue: MapLayerStyle.CuratedRoads.sharedDashPattern)
            shared.lineJoin = NSExpression(forConstantValue: "round")
            shared.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(shared)

            addedSources.insert(id)
        }
    }
}
