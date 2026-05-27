import Foundation

final class MockHealthDataProvider: HealthDataProvider {
    var simulatedStatus: HealthPermissionStatus

    /// Returns all workout sessions ever logged. Used to compute per-day kcal
    /// straight from the history, so the calendar value for a date always matches
    /// the sum of that day's History entries (and survives app restarts).
    var sessionsProvider: () -> [WorkoutSession] = { [] }

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    init(status: HealthPermissionStatus = .authorized) {
        self.simulatedStatus = status
    }

    func checkPermissionStatus() async -> HealthPermissionStatus {
        simulatedStatus
    }

    func requestPermission() async -> HealthPermissionStatus {
        simulatedStatus = .authorized
        return simulatedStatus
    }

    func fetchTodayActiveCalories() async throws -> Double {
        try await fetchActiveCalories(on: Date())
    }

    func fetchActiveCalories(on date: Date) async throws -> Double {
        let calendar = Calendar.current
        let sessions = sessionsProvider()
        let kcalFromSessions = sessions
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.caloriesBurned }

        if kcalFromSessions > 0 {
            return Double(kcalFromSessions)
        }
        // Today with no sessions starts at 0.
        if calendar.isDateInToday(date) { return 0 }
        // Past days with no sessions get a believable baseline.
        return Self.seededBaseline(for: date)
    }

    func writeWorkoutCalories(_ kcal: Double, date: Date) async throws {
        // Sessions are the source of truth — no separate write needed.
        // (Kept as a no-op so the protocol contract is still satisfied.)
    }

    private static func seededBaseline(for date: Date) -> Double {
        // Deterministic pseudo-random baseline per day so past days look plausible.
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        let base = 250 + (day * 37) % 400
        return Double(base)
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
