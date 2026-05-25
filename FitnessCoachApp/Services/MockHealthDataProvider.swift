import Foundation

final class MockHealthDataProvider: HealthDataProvider {
    var simulatedStatus: HealthPermissionStatus
    var simulatedCalories: Double

    init(status: HealthPermissionStatus = .authorized, calories: Double = 342) {
        self.simulatedStatus = status
        self.simulatedCalories = calories
    }

    func checkPermissionStatus() async -> HealthPermissionStatus {
        simulatedStatus
    }

    func requestPermission() async -> HealthPermissionStatus {
        simulatedStatus = .authorized
        return simulatedStatus
    }

    func fetchTodayActiveCalories() async throws -> Double {
        simulatedCalories
    }

    func writeWorkoutCalories(_ kcal: Double, date: Date) async throws {
        simulatedCalories += kcal
    }

    /// Builds a believable 7-day rollup for the AI Coach demo. Values vary by
    /// day so the AI has something interesting to comment on (active vs lazy
    /// days, sleep dips, etc.).
    func fetchWeeklySnapshot(goalActiveKcal: Int) async -> HealthSnapshot? {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // Day-of-week-flavored numbers — Mon-Fri lighter, weekends more active.
        let templates: [(steps: Int, active: Int, exMin: Int, hr: Int, workouts: Int, sleep: Double)] = [
            (7204, 312, 28, 68, 0, 7.2),
            (11032, 489, 45, 72, 1, 6.8),
            (4861, 201, 12, 65, 0, 7.5),
            (12540, 534, 60, 74, 1, 6.5),
            (10888, 478, 42, 71, 1, 7.0),
            (8743, 389, 35, 69, 0, 8.1),
            (9610, 444, 38, 70, 1, 7.8),
        ]

        var entries: [DailyHealthEntry] = []
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now

        for (i, t) in templates.enumerated() {
            let dayDate = calendar.date(byAdding: .day, value: i, to: weekStart) ?? weekStart
            let resting = 1640 + Int.random(in: -20...30)
            entries.append(DailyHealthEntry(
                date: formatter.string(from: dayDate),
                steps: t.steps,
                activeKcal: t.active,
                restingKcal: resting,
                exerciseMinutes: t.exMin,
                avgHeartRate: t.hr,
                workoutCount: t.workouts,
                sleepHours: t.sleep
            ))
        }

        let totalSteps = entries.reduce(0) { $0 + $1.steps }
        let totalActive = entries.reduce(0) { $0 + $1.activeKcal }
        let totalResting = entries.reduce(0) { $0 + $1.restingKcal }
        let totalEx = entries.reduce(0) { $0 + $1.exerciseMinutes }
        let totalWorkouts = entries.reduce(0) { $0 + $1.workoutCount }
        let avgHR = entries.map(\.avgHeartRate).reduce(0, +) / entries.count
        let avgSleep = entries.map(\.sleepHours).reduce(0, +) / Double(entries.count)

        let totals = WeeklyTotals(
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

        let endDate = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return HealthSnapshot(
            periodStart: formatter.string(from: weekStart),
            periodEnd: formatter.string(from: endDate),
            dailyEntries: entries,
            weeklyTotals: totals,
            dataSource: "mock"
        )
    }
}
