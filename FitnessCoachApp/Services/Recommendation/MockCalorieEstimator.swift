import Foundation

/// MET-based calorie estimator. Used for previews, tests, and offline fallback.
///
/// MET (Metabolic Equivalent of Task) is the standard way to estimate energy
/// cost: `kcal = MET × weight(kg) × hours`. Defaults to a moderate MET if the
/// activity isn't in the table.
struct MockCalorieEstimator: CalorieEstimating {

    /// Approximate MET values from the Compendium of Physical Activities,
    /// keyed by lowercased substring match. Conservative on the high end.
    private static let metTable: [(keyword: String, met: Double)] = [
        ("sprint", 12.0),
        ("burpee", 10.0),
        ("hiit", 9.5),
        ("rowing", 8.0),
        ("jog", 7.0),
        ("mountain climb", 8.0),
        ("jumping jack", 7.7),
        ("lunge", 5.5),
        ("push-up", 5.5),
        ("pushup", 5.5),
        ("plank", 4.0),
        ("squat", 5.0),
        ("cycle", 6.0),
        ("bike", 6.0),
        ("brisk walk", 4.3),
        ("walk", 3.5),
        ("yoga", 2.5),
        ("stretch", 2.3),
        ("foam roll", 2.0),
        ("mobility", 2.3),
    ]

    private static let defaultMET: Double = 4.0
    private static let defaultWeightPounds: Double = 165.0

    func estimateCalories(
        activityName: String,
        weightPounds: Double?,
        durationMinutes: Int
    ) async throws -> CalorieEstimate {
        let met = Self.metFor(activityName)
        let weightKg = (weightPounds ?? Self.defaultWeightPounds) * 0.45359237
        let hours = Double(max(durationMinutes, 0)) / 60.0
        let total = met * weightKg * hours
        let perHour = met * weightKg
        return CalorieEstimate(
            totalCalories: total.rounded(),
            caloriesPerHour: perHour.rounded(),
            sourceProvider: "mock-MET"
        )
    }

    private static func metFor(_ activity: String) -> Double {
        let lower = activity.lowercased()
        for (keyword, met) in metTable where lower.contains(keyword) {
            return met
        }
        return defaultMET
    }
}
