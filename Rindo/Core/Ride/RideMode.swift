import Foundation

/// 走行モード — 音声案内頻度・ナビズーム・リマインダー有無を制御
enum RideMode: String, CaseIterable, Identifiable {
    case commute   // 通勤
    case leisure   // レジャー
    case training  // トレーニング

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commute:  "通勤"
        case .leisure:  "レジャー"
        case .training: "トレーニング"
        }
    }

    var icon: String {
        switch self {
        case .commute:  "briefcase"
        case .leisure:  "bicycle"
        case .training: "figure.outdoor.cycle"
        }
    }

    /// 音声案内のトリガ距離（メートル）。降順で、最初に該当した閾値で発話。
    var voiceTriggerDistances: [Double] {
        switch self {
        case .commute:  [200, 100, 50]
        case .leisure:  [500, 200, 100, 50]
        case .training: [100, 50]
        }
    }

    /// ナビ開始時のデフォルトズームレベル
    var navZoomLevel: Double {
        switch self {
        case .commute:  18
        case .leisure:  17
        case .training: 19
        }
    }

    /// 休憩・補給リマインダーを有効にするか
    var remindersEnabled: Bool {
        switch self {
        case .commute:  false
        case .leisure:  true
        case .training: true
        }
    }

    var description: String {
        switch self {
        case .commute:  "短距離向け。標準の音声案内、リマインダーなし"
        case .leisure:  "長距離向け。早めの音声案内、リマインダーあり"
        case .training: "最小限の音声案内、リマインダーあり"
        }
    }
}
