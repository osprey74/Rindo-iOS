import Foundation
import CoreLocation

struct ElevationPoint: Sendable {
    let distanceKm: Double
    let elevationM: Double
}

struct ElevationProfile: Sendable {
    let points: [ElevationPoint]
    let totalDistanceKm: Double
    let totalAscentM: Double
    let totalDescentM: Double
    let maxSlopePct: Double
    let minElevationM: Double
    let maxElevationM: Double
}

enum ElevationService {
    private static let targetSamples = 60

    /// GPX の ele タグデータから ElevationProfile を生成（API 不要）
    static func createProfileFromGPX(
        coordinates: [CLLocationCoordinate2D],
        elevations: [Double]
    ) -> ElevationProfile? {
        guard coordinates.count >= 2, coordinates.count == elevations.count else { return nil }

        // 累積距離を計算
        var cumulative: [Double] = [0]
        for i in 1..<coordinates.count {
            let prev = CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
            let curr = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            cumulative.append(cumulative[i - 1] + prev.distance(from: curr))
        }

        // targetSamples にダウンサンプリング
        let step = max(1, coordinates.count / targetSamples)
        var points: [ElevationPoint] = []
        for i in stride(from: 0, to: coordinates.count, by: step) {
            points.append(ElevationPoint(
                distanceKm: cumulative[i] / 1000,
                elevationM: elevations[i]
            ))
        }
        // 最終点を必ず含める
        if let last = points.last, last.distanceKm != cumulative.last! / 1000 {
            points.append(ElevationPoint(
                distanceKm: cumulative.last! / 1000,
                elevationM: elevations.last!
            ))
        }

        var totalAscent = 0.0
        var totalDescent = 0.0
        var maxSlope = 0.0
        for i in 1..<points.count {
            let dz = points[i].elevationM - points[i - 1].elevationM
            let dxM = (points[i].distanceKm - points[i - 1].distanceKm) * 1000
            if dz > 0 { totalAscent += dz }
            else { totalDescent += -dz }
            if dxM > 0 {
                let slope = abs(dz / dxM * 100)
                if slope > maxSlope { maxSlope = slope }
            }
        }

        let elevationValues = points.map(\.elevationM)
        return ElevationProfile(
            points: points,
            totalDistanceKm: points.last?.distanceKm ?? 0,
            totalAscentM: totalAscent,
            totalDescentM: totalDescent,
            maxSlopePct: maxSlope,
            minElevationM: elevationValues.min() ?? 0,
            maxElevationM: elevationValues.max() ?? 0
        )
    }

    /// ルート geometry の coordinates からサンプリングして標高プロファイルを取得
    static func fetchProfile(coordinates: [[Double]]) async throws -> ElevationProfile {
        guard coordinates.count >= 2 else {
            throw ElevationError.tooFewPoints
        }

        let samples = sampleRoute(coordinates)
        let elevations = try await fetchElevations(samples)

        var points: [ElevationPoint] = []
        for (i, sample) in samples.enumerated() {
            points.append(ElevationPoint(
                distanceKm: sample.cumulativeM / 1000,
                elevationM: elevations[i]
            ))
        }

        var totalAscent = 0.0
        var totalDescent = 0.0
        var maxSlope = 0.0
        for i in 1..<points.count {
            let dz = points[i].elevationM - points[i - 1].elevationM
            let dxM = (points[i].distanceKm - points[i - 1].distanceKm) * 1000
            if dz > 0 { totalAscent += dz }
            else { totalDescent += -dz }
            if dxM > 0 {
                let slope = abs(dz / dxM * 100)
                if slope > maxSlope { maxSlope = slope }
            }
        }

        let elevationValues = points.map(\.elevationM)
        return ElevationProfile(
            points: points,
            totalDistanceKm: points.last?.distanceKm ?? 0,
            totalAscentM: totalAscent,
            totalDescentM: totalDescent,
            maxSlopePct: maxSlope,
            minElevationM: elevationValues.min() ?? 0,
            maxElevationM: elevationValues.max() ?? 0
        )
    }

    // MARK: - Sampling

    private struct Sample {
        let lon: Double
        let lat: Double
        let cumulativeM: Double
    }

    private static func sampleRoute(_ coordinates: [[Double]]) -> [Sample] {
        guard !coordinates.isEmpty else { return [] }

        // 累積距離を計算
        var cumulative: [Double] = [0]
        for i in 1..<coordinates.count {
            let prev = CLLocation(latitude: coordinates[i - 1][1], longitude: coordinates[i - 1][0])
            let curr = CLLocation(latitude: coordinates[i][1], longitude: coordinates[i][0])
            cumulative.append(cumulative[i - 1] + prev.distance(from: curr))
        }

        if coordinates.count <= targetSamples {
            return coordinates.enumerated().map { (i, coord) in
                Sample(lon: coord[0], lat: coord[1], cumulativeM: cumulative[i])
            }
        }

        let step = Double(coordinates.count - 1) / Double(targetSamples - 1)
        var samples: [Sample] = []
        for i in 0..<targetSamples {
            let idx = i == targetSamples - 1
                ? coordinates.count - 1
                : Int((Double(i) * step).rounded())
            let coord = coordinates[idx]
            samples.append(Sample(lon: coord[0], lat: coord[1], cumulativeM: cumulative[idx]))
        }
        return samples
    }

    // MARK: - API

    private struct OpenTopoResponse: Codable {
        let status: String
        let results: [Result]
        let error: String?

        struct Result: Codable {
            let elevation: Double?
        }
    }

    private static func fetchElevations(_ samples: [Sample]) async throws -> [Double] {
        let locations = samples.map { "\($0.lat),\($0.lon)" }.joined(separator: "|")
        let body = ["locations": locations]
        let response = try await APIClient.shared.post(
            OpenTopoResponse.self,
            path: "/api/elevation",
            body: body,
            baseURL: AppConfig.caddyBaseURL
        )
        guard response.status == "OK" else {
            throw ElevationError.apiFailed(response.error ?? response.status)
        }
        return response.results.map { $0.elevation ?? 0 }
    }

    enum ElevationError: LocalizedError {
        case tooFewPoints
        case apiFailed(String)

        var errorDescription: String? {
            switch self {
            case .tooFewPoints: "標高プロファイルには 2 点以上必要です"
            case .apiFailed(let msg): "標高取得失敗: \(msg)"
            }
        }
    }
}
