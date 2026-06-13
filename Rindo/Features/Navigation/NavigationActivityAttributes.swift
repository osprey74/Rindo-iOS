import ActivityKit
import Foundation

struct NavigationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let maneuverIcon: String
        let instruction: String
        let distanceToNextM: Double
        let remainingDistanceKm: Double
        let remainingTimeSeconds: Double
    }
}
