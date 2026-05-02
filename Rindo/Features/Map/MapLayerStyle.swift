import UIKit

/// Web 版 (mapStyle.ts / MapView.tsx) と同一のスタイル定義
enum MapLayerStyle {

    // MARK: - Layer 1: OSM Cycleways (highway=cycleway)

    enum OSMCycleways {
        static let sourceID = "osm-cycleways"
        static let layerID = "osm-cycleways-line"
        static let color = UIColor(red: 0x1D/255, green: 0x9E/255, blue: 0x75/255, alpha: 1) // #1D9E75
        static let width: CGFloat = 3
        static let opacity: Float = 0.85
    }

    // MARK: - Layer 2: OSM Bicycle Routes (route=bicycle)

    enum BicycleRoutes {
        static let sourceID = "bicycle-routes"
        static let layerID = "bicycle-routes-line"
        static let color = UIColor(red: 0x3C/255, green: 0x7B/255, blue: 0x91/255, alpha: 1) // #3C7B91
        static let width: CGFloat = 4
        static let opacity: Float = 0.9
    }

    // MARK: - Layer 3: Curated Cycling Roads

    enum CuratedRoads {
        static let sourceID = "cycling-roads"
        static let exclusiveLayerID = "cycling-roads-exclusive"
        static let sharedLayerID = "cycling-roads-shared"
        static let color = UIColor(red: 0xE6/255, green: 0x5C/255, blue: 0x00/255, alpha: 1) // #E65C00
        static let exclusiveWidth: CGFloat = 4
        static let sharedWidth: CGFloat = 2
        static let sharedDashPattern: [NSNumber] = [4, 2]
    }
}
