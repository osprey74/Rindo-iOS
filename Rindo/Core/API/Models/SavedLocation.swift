import Foundation
import CoreLocation

struct LocationsResponse: Codable, Sendable {
    let locations: [SavedLocation]
}

struct SavedLocation: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let category: LocationCategory
    let lon: Double
    let lat: Double
    let notes: String?
    let createdAt: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

enum LocationCategory: String, Codable, Sendable, CaseIterable {
    case home, work, favorite, other

    var displayName: String {
        switch self {
        case .home: "自宅"
        case .work: "職場"
        case .favorite: "お気に入り"
        case .other: "その他"
        }
    }

    var emoji: String {
        switch self {
        case .home: "🏠"
        case .work: "🏢"
        case .favorite: "⭐"
        case .other: "📍"
        }
    }

    var markerColor: String {
        switch self {
        case .home: "#4A90D9"
        case .work: "#7B68EE"
        case .favorite: "#FFD700"
        case .other: "#888888"
        }
    }
}
