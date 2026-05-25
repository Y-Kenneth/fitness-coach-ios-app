import Foundation

/// A 7-day rollup of the user's health data, packaged to send to the AI Coach
/// backend. All fields are Encodable so this can be POSTed as JSON.
///
/// Field names use snake_case in JSON to match what the Flask/CrewAI prompt
/// formatter expects on the server side.
struct HealthSnapshot: Codable, Equatable {
    let periodStart: String          // ISO yyyy-MM-dd
    let periodEnd: String            // ISO yyyy-MM-dd
    let dailyEntries: [DailyHealthEntry]
    let weeklyTotals: WeeklyTotals
    let dataSource: String           // "healthkit", "mock", or "empty"

    enum CodingKeys: String, CodingKey {
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case dailyEntries = "daily_entries"
        case weeklyTotals = "weekly_totals"
        case dataSource = "data_source"
    }
}

struct DailyHealthEntry: Codable, Equatable {
    let date: String                 // yyyy-MM-dd
    let steps: Int
    let activeKcal: Int
    let restingKcal: Int
    let exerciseMinutes: Int
    let avgHeartRate: Int            // 0 if unavailable
    let workoutCount: Int
    let sleepHours: Double           // 0 if unavailable

    enum CodingKeys: String, CodingKey {
        case date
        case steps
        case activeKcal = "active_kcal"
        case restingKcal = "resting_kcal"
        case exerciseMinutes = "exercise_minutes"
        case avgHeartRate = "avg_heart_rate"
        case workoutCount = "workout_count"
        case sleepHours = "sleep_hours"
    }
}

struct WeeklyTotals: Codable, Equatable {
    let totalSteps: Int
    let totalActiveKcal: Int
    let totalRestingKcal: Int
    let totalExerciseMinutes: Int
    let totalWorkouts: Int
    let avgRestingHeartRate: Int     // 0 if no data
    let avgSleepHours: Double        // 0 if no data
    let dailyAverageActiveKcal: Double
    let dailyAverageSteps: Int
    let goalActiveKcalPerDay: Int

    enum CodingKeys: String, CodingKey {
        case totalSteps = "total_steps"
        case totalActiveKcal = "total_active_kcal"
        case totalRestingKcal = "total_resting_kcal"
        case totalExerciseMinutes = "total_exercise_minutes"
        case totalWorkouts = "total_workouts"
        case avgRestingHeartRate = "avg_resting_heart_rate"
        case avgSleepHours = "avg_sleep_hours"
        case dailyAverageActiveKcal = "daily_average_active_kcal"
        case dailyAverageSteps = "daily_average_steps"
        case goalActiveKcalPerDay = "goal_active_kcal_per_day"
    }
}
