import HealthKit
import Foundation

final class LiveHealthDataProvider: HealthDataProvider {
    private let store = HKHealthStore()
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let restingEnergyType = HKQuantityType(.basalEnergyBurned)
    private let stepsType = HKQuantityType(.stepCount)
    private let exerciseTimeType = HKQuantityType(.appleExerciseTime)
    private let heartRateType = HKQuantityType(.heartRate)
    private let sleepType = HKCategoryType(.sleepAnalysis)

    private var readTypes: Set<HKObjectType> {
        [energyType, restingEnergyType, stepsType, exerciseTimeType,
         heartRateType, sleepType, HKWorkoutType.workoutType()]
    }

    private var writeTypes: Set<HKSampleType> {
        [energyType]
    }

    // MARK: Permission

    func checkPermissionStatus() async -> HealthPermissionStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        do {
            let status = try await store.statusForAuthorizationRequest(
                toShare: writeTypes,
                read: readTypes
            )
            return status == .shouldRequest ? .notDetermined : .authorized
        } catch {
            return .notDetermined
        }
    }

    func requestPermission() async -> HealthPermissionStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return await checkPermissionStatus()
        } catch {
            return .denied
        }
    }

    // MARK: Today's active calories (existing API, unchanged behavior)

    func fetchTodayActiveCalories() async throws -> Double {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.unavailable }
        let start = Calendar.current.startOfDay(for: .now)
        return try await sumQuantity(type: energyType, unit: .kilocalorie(), from: start, to: .now)
    }

    func fetchActiveCalories(on date: Date) async throws -> Double {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.unavailable }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return try await sumQuantity(type: energyType, unit: .kilocalorie(), from: start, to: end)
    }

    func writeWorkoutCalories(_ kcal: Double, date: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.unavailable }
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        let sample = HKQuantitySample(type: energyType, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }

    // MARK: Weekly snapshot for AI Coach

    func fetchWeeklySnapshot(goalActiveKcal: Int) async -> HealthSnapshot? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        let calendar = Calendar.current
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: .now) ?? .now
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now

        var dailyEntries: [DailyHealthEntry] = []
        var hasAnyData = false

        for dayOffset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) else { continue }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            async let steps = (try? sumQuantity(type: stepsType, unit: .count(), from: dayStart, to: dayEnd)) ?? 0
            async let activeKcal = (try? sumQuantity(type: energyType, unit: .kilocalorie(), from: dayStart, to: dayEnd)) ?? 0
            async let restingKcal = (try? sumQuantity(type: restingEnergyType, unit: .kilocalorie(), from: dayStart, to: dayEnd)) ?? 0
            async let exerciseMin = (try? sumQuantity(type: exerciseTimeType, unit: .minute(), from: dayStart, to: dayEnd)) ?? 0
            async let avgHR = (try? averageQuantity(type: heartRateType, unit: HKUnit.count().unitDivided(by: .minute()), from: dayStart, to: dayEnd)) ?? 0
            async let workouts = (try? workoutCount(from: dayStart, to: dayEnd)) ?? 0
            async let sleep = (try? sleepHours(from: dayStart, to: dayEnd)) ?? 0

            let entry = await DailyHealthEntry(
                date: Self.iso(dayStart),
                steps: Int(steps),
                activeKcal: Int(activeKcal),
                restingKcal: Int(restingKcal),
                exerciseMinutes: Int(exerciseMin),
                avgHeartRate: Int(avgHR),
                workoutCount: workouts,
                sleepHours: sleep
            )
            dailyEntries.append(entry)

            if entry.steps > 0 || entry.activeKcal > 0 || entry.workoutCount > 0 {
                hasAnyData = true
            }
        }

        guard hasAnyData else { return nil }

        let totals = buildTotals(from: dailyEntries, goalActiveKcal: goalActiveKcal)

        return HealthSnapshot(
            periodStart: Self.iso(startOfWeek),
            periodEnd: Self.iso(endOfToday),
            dailyEntries: dailyEntries,
            weeklyTotals: totals,
            dataSource: "healthkit"
        )
    }

    // MARK: Helpers — HK queries

    private func sumQuantity(type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0)
                }
            }
            store.execute(query)
        }
    }

    private func averageQuantity(type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?.averageQuantity()?.doubleValue(for: unit) ?? 0)
                }
            }
            store.execute(query)
        }
    }

    private func workoutCount(from start: Date, to end: Date) async throws -> Int {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.count ?? 0)
                }
            }
            store.execute(query)
        }
    }

    private func sleepHours(from start: Date, to end: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let asleep: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let totalSeconds = (samples as? [HKCategorySample])?
                    .filter { asleep.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
                continuation.resume(returning: totalSeconds / 3600.0)
            }
            store.execute(query)
        }
    }

    private func buildTotals(from entries: [DailyHealthEntry], goalActiveKcal: Int) -> WeeklyTotals {
        let totalSteps = entries.reduce(0) { $0 + $1.steps }
        let totalActive = entries.reduce(0) { $0 + $1.activeKcal }
        let totalResting = entries.reduce(0) { $0 + $1.restingKcal }
        let totalEx = entries.reduce(0) { $0 + $1.exerciseMinutes }
        let totalWorkouts = entries.reduce(0) { $0 + $1.workoutCount }
        let hrValues = entries.map(\.avgHeartRate).filter { $0 > 0 }
        let sleepValues = entries.map(\.sleepHours).filter { $0 > 0 }
        let avgHR = hrValues.isEmpty ? 0 : hrValues.reduce(0, +) / hrValues.count
        let avgSleep = sleepValues.isEmpty ? 0 : sleepValues.reduce(0, +) / Double(sleepValues.count)

        return WeeklyTotals(
            totalSteps: totalSteps,
            totalActiveKcal: totalActive,
            totalRestingKcal: totalResting,
            totalExerciseMinutes: totalEx,
            totalWorkouts: totalWorkouts,
            avgRestingHeartRate: avgHR,
            avgSleepHours: avgSleep,
            dailyAverageActiveKcal: Double(totalActive) / 7.0,
            dailyAverageSteps: totalSteps / 7,
            goalActiveKcalPerDay: goalActiveKcal
        )
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
}
