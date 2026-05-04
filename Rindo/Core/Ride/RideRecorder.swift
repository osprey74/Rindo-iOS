import CoreLocation
import Foundation
import SwiftData

/// 走行記録を管理する。LocationService から位置情報を受け取り、
/// TrackPoint を蓄積し、走行統計をリアルタイム更新する。
@Observable
@MainActor
final class RideRecorder {
    // 走行状態
    enum State: Sendable { case idle, recording, paused }
    private(set) var state: State = .idle
    var isRecording: Bool { state == .recording }

    // リアルタイム統計
    private(set) var speedKmh: Double = 0
    private(set) var totalDistanceM: Double = 0
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var currentAltitude: Double = 0
    private(set) var gradePercent: Double = 0
    private(set) var caloriesKcal: Double = 0
    private(set) var maxSpeedKmh: Double = 0
    private(set) var course: Double = 0

    // トラックポイント
    private(set) var trackPoints: [RecordedTrackPoint] = []

    // 設定
    var weightKg: Double = 70
    var reminderManager: ReminderManager?

    // 内部
    private var startTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStart: Date?
    private var lastLocation: CLLocation?
    private var timer: Timer?

    // 勾配計算用（10秒窓）
    private var recentAltitudes: [(time: Date, altitude: Double)] = []

    struct RecordedTrackPoint: Sendable {
        let coordinate: CLLocationCoordinate2D
        let altitude: Double
        let timestamp: Date
        let speed: Double // m/s
    }

    // MARK: - Controls

    func start() {
        guard state == .idle else { return }
        state = .recording
        startTime = Date()
        pausedDuration = 0
        totalDistanceM = 0
        elapsedSeconds = 0
        caloriesKcal = 0
        maxSpeedKmh = 0
        trackPoints = []
        lastLocation = nil
        recentAltitudes = []
        reminderManager?.reset()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        pauseStart = Date()
    }

    func resume() {
        guard state == .paused else { return }
        if let ps = pauseStart {
            pausedDuration += Date().timeIntervalSince(ps)
        }
        pauseStart = nil
        state = .recording
    }

    func stop() -> RideSummary? {
        timer?.invalidate()
        timer = nil
        guard let start = startTime, trackPoints.count >= 2 else {
            state = .idle
            return nil
        }
        // 一時停止中に停止した場合
        if let ps = pauseStart {
            pausedDuration += Date().timeIntervalSince(ps)
        }

        let end = Date()
        let summary = RideSummary(
            startedAt: start,
            endedAt: end,
            distanceKm: totalDistanceM / 1000,
            durationMin: elapsedSeconds / 60,
            ascentM: computeAscent(),
            descentM: computeDescent(),
            maxSpeedKmh: maxSpeedKmh,
            avgSpeedKmh: elapsedSeconds > 0 ? (totalDistanceM / 1000) / (elapsedSeconds / 3600) : 0,
            caloriesKcal: caloriesKcal,
            trackPoints: trackPoints
        )
        state = .idle
        return summary
    }

    // MARK: - Location Update (called from LocationService)

    func handleLocation(_ location: CLLocation) {
        guard state == .recording else { return }

        let point = RecordedTrackPoint(
            coordinate: location.coordinate,
            altitude: location.altitude,
            timestamp: location.timestamp,
            speed: max(0, location.speed)
        )
        trackPoints.append(point)

        // 速度
        speedKmh = max(0, location.speed * 3.6)
        if speedKmh > maxSpeedKmh { maxSpeedKmh = speedKmh }

        // 方向
        if location.course >= 0 && location.speed > 0.5 {
            course = location.course
        }

        // 距離
        if let last = lastLocation {
            totalDistanceM += location.distance(from: last)
        }
        lastLocation = location

        // 標高
        currentAltitude = location.altitude

        // 勾配（10秒窓）
        updateGrade(altitude: location.altitude, time: location.timestamp)

        // カロリー（MET ベース、毎秒加算）
        let met = 7.5 * (1 + max(0, gradePercent) * 0.1)
        caloriesKcal += met * weightKg * (1.0 / 3600.0) // 1秒分
    }

    // MARK: - Private

    private func tick() {
        guard state == .recording, let start = startTime else { return }
        elapsedSeconds = Date().timeIntervalSince(start) - pausedDuration
        reminderManager?.check(elapsedSeconds: elapsedSeconds, totalDistanceM: totalDistanceM)
    }

    private func updateGrade(altitude: Double, time: Date) {
        recentAltitudes.append((time: time, altitude: altitude))
        // 10秒より古いデータを除去
        let cutoff = time.addingTimeInterval(-10)
        recentAltitudes.removeAll { $0.time < cutoff }

        guard recentAltitudes.count >= 2 else { gradePercent = 0; return }
        let first = recentAltitudes.first!
        let last = recentAltitudes.last!
        let dt = last.time.timeIntervalSince(first.time)
        guard dt > 1 else { return }

        let dAlt = last.altitude - first.altitude
        // 水平距離は速度×時間で概算
        let horizontalM = speedKmh / 3.6 * dt
        if horizontalM > 1 {
            gradePercent = (dAlt / horizontalM) * 100
        }
    }

    private func computeAscent() -> Double {
        var ascent = 0.0
        for i in 1..<trackPoints.count {
            let dz = trackPoints[i].altitude - trackPoints[i - 1].altitude
            if dz > 0 { ascent += dz }
        }
        return ascent
    }

    private func computeDescent() -> Double {
        var descent = 0.0
        for i in 1..<trackPoints.count {
            let dz = trackPoints[i].altitude - trackPoints[i - 1].altitude
            if dz < 0 { descent += -dz }
        }
        return descent
    }
}

/// 走行終了時のサマリー（SwiftData 保存 + サーバアップロード用）
struct RideSummary: Sendable {
    let startedAt: Date
    let endedAt: Date
    let distanceKm: Double
    let durationMin: Double
    let ascentM: Double
    let descentM: Double
    let maxSpeedKmh: Double
    let avgSpeedKmh: Double
    let caloriesKcal: Double
    let trackPoints: [RideRecorder.RecordedTrackPoint]
}
