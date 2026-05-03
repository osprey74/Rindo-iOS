import Foundation

/// Valhalla マニューバ type を SF Symbol アイコンにマッピング
enum ManeuverParser {
    /// SF Symbol name for the maneuver type
    static func iconName(for type: Int) -> String {
        switch type {
        case 0:  return "arrow.up"            // kNone
        case 1:  return "flag"                // kStart
        case 2:  return "flag"                // kStartRight
        case 3:  return "flag"                // kStartLeft
        case 4:  return "mappin.circle.fill"  // kDestination
        case 5:  return "mappin.circle.fill"  // kDestinationRight
        case 6:  return "mappin.circle.fill"  // kDestinationLeft
        case 7:  return "arrow.up"            // kBecomes
        case 8:  return "arrow.up"            // kContinue
        case 9:  return "arrow.up.right"      // kSlightRight
        case 10: return "arrow.turn.up.right" // kRight
        case 11: return "arrow.turn.up.right" // kSharpRight
        case 12: return "arrow.uturn.right"   // kUturnRight
        case 13: return "arrow.uturn.left"    // kUturnLeft
        case 14: return "arrow.turn.up.left"  // kSharpLeft
        case 15: return "arrow.turn.up.left"  // kLeft
        case 16: return "arrow.up.left"       // kSlightLeft
        case 17: return "arrow.up"            // kRampStraight
        case 18: return "arrow.up.right"      // kRampRight
        case 19: return "arrow.up.left"       // kRampLeft
        case 20: return "arrow.up.right"      // kExitRight
        case 21: return "arrow.up.left"       // kExitLeft
        case 22: return "arrow.up"            // kStayStraight
        case 23: return "arrow.up.right"      // kStayRight
        case 24: return "arrow.up.left"       // kStayLeft
        case 25: return "arrow.merge"         // kMerge
        case 26: return "arrow.triangle.capsulepath" // kRoundaboutEnter
        case 27: return "arrow.triangle.capsulepath" // kRoundaboutExit
        default: return "arrow.up"
        }
    }

    /// 目的地系のマニューバかどうか
    static func isDestination(_ type: Int) -> Bool {
        (4...6).contains(type)
    }
}
