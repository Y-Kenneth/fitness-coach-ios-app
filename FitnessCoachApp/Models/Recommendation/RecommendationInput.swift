import Foundation

/// Everything the recommendation engine needs to pick a plan.
/// Kept explicit (no optionals that hide important context) so the rules
/// are easy to reason about.
struct RecommendationInput: Hashable {
    var targetCalories: Double
    var activeEnergyBurned: Double
    var availableMinutes: Int
    var preferredIntensity: WorkoutIntensity
    var bodyWeightPounds: Double?
    var recentSessions: [WorkoutSessionSummary]

    /// kcal still to burn to hit today's goal. Can be negative if the user
    /// already exceeded the goal; the engine treats that as "recover" mode.
    var remainingCalories: Double {
        targetCalories - activeEnergyBurned
    }
}

/// Compact summary of a past workout, used by the engine to avoid suggesting
/// the same thing two days in a row.
struct WorkoutSessionSummary: Codable, Hashable {
    var date: Date
    var title: String
    var intensity: WorkoutIntensity
    var durationMinutes: Int
}
