import Foundation
import HealthKit

/// HealthKit 連携 — 体重取得 + サイクリングワークアウト書き戻し
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private var authorized = false

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.bodyMass),
        ]
        let writeTypes: Set<HKSampleType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceCycling),
            HKWorkoutType.workoutType(),
        ]

        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            authorized = true
            return true
        } catch {
            return false
        }
    }

    // MARK: - Body Mass

    /// 最新の体重を kg で取得。取得失敗時は nil
    func fetchBodyMass() async -> Double? {
        guard authorized else { return nil }

        let type = HKQuantityType(.bodyMass)
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )

        do {
            let results = try await query.result(for: store)
            return results.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
        } catch {
            return nil
        }
    }

    // MARK: - Workout Write-back

    /// 走行記録を HKWorkout として HealthKit に書き戻す
    func saveWorkout(
        startDate: Date,
        endDate: Date,
        distanceKm: Double,
        caloriesKcal: Double
    ) async -> Bool {
        guard authorized else { return false }

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        do {
            try await builder.beginCollection(at: startDate)

            // 距離
            let distanceSample = HKQuantitySample(
                type: HKQuantityType(.distanceCycling),
                quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: distanceKm),
                start: startDate,
                end: endDate
            )
            // カロリー
            let calorieSample = HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: caloriesKcal),
                start: startDate,
                end: endDate
            )

            try await builder.addSamples([distanceSample, calorieSample])
            try await builder.endCollection(at: endDate)
            try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }
}
