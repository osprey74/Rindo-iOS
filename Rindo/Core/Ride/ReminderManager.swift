import Foundation
import UserNotifications

/// 走行中の休憩・補給リマインダー
/// RideRecorder の 1 秒タイマ（tick）から check() が呼ばれる
@Observable
@MainActor
final class ReminderManager {
    /// 休憩リマインダー間隔（分）。0 で無効
    var breakIntervalMinutes: Int = 60
    /// 補給リマインダー間隔（km）。0 で無効
    var refuelIntervalKm: Double = 50

    /// 音声案内用（外部から設定）
    var voiceGuide: VoiceGuide?

    // 発火済みマーク（重複防止）
    private var firedBreakMarks: Set<Int> = []
    private var firedRefuelMarks: Set<Int> = []

    /// ライド開始時にリセット
    func reset() {
        firedBreakMarks.removeAll()
        firedRefuelMarks.removeAll()
    }

    /// 毎秒呼ばれる — 条件を満たせばリマインダーを発火
    func check(elapsedSeconds: TimeInterval, totalDistanceM: Double) {
        checkBreak(elapsedSeconds: elapsedSeconds)
        checkRefuel(totalDistanceKm: totalDistanceM / 1000)
    }

    // MARK: - Private

    private func checkBreak(elapsedSeconds: TimeInterval) {
        guard breakIntervalMinutes > 0 else { return }
        let mark = Int(elapsedSeconds) / (breakIntervalMinutes * 60)
        guard mark > 0, !firedBreakMarks.contains(mark) else { return }
        firedBreakMarks.insert(mark)

        let minutes = mark * breakIntervalMinutes
        let msg = "\(minutes)分経過しました。休憩しませんか？"
        voiceGuide?.speak(msg, key: "break_\(mark)")
        sendNotification(title: "休憩リマインダー", body: msg)
    }

    private func checkRefuel(totalDistanceKm: Double) {
        guard refuelIntervalKm > 0 else { return }
        let mark = Int(totalDistanceKm / refuelIntervalKm)
        guard mark > 0, !firedRefuelMarks.contains(mark) else { return }
        firedRefuelMarks.insert(mark)

        let km = Int(Double(mark) * refuelIntervalKm)
        let msg = "\(km)km走行しました。補給を検討してください。"
        voiceGuide?.speak(msg, key: "refuel_\(mark)")
        sendNotification(title: "補給リマインダー", body: msg)
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 通知パーミッションのリクエスト（アプリ起動時に1回呼ぶ）
    static func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
