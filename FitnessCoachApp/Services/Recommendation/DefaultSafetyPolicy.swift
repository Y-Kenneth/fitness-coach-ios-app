import Foundation

/// Applies the lesson's safety guardrails (slide 15).
///
/// Returns warnings when a plan is technically fine but worth flagging,
/// and rejections (needsLowerIntensity / needsShorterDuration) when the
/// engine should retry with adjusted parameters.
struct DefaultSafetyPolicy: WorkoutSafetyChecking {

    /// Hard upper bounds. A plan exceeding these is rejected.
    static let maxIntensiveDuration = 45
    static let maxAnyDuration = 120
    static let maxKcalPerMinute: Double = 18.0   // sanity-check estimate

    /// Soft thresholds — produce warnings, not rejections.
    static let recommendedWarmUpMinimum = 3
    static let recommendedCooldownMinimum = 3

    func validate(_ plan: WorkoutPlan, input: RecommendationInput) -> SafetyResult {

        // Hard rejections first.
        if plan.intensity == .intense, plan.durationMinutes > Self.maxIntensiveDuration {
            return .needsShorterDuration(
                reason: "Intense sessions should stay under \(Self.maxIntensiveDuration) minutes."
            )
        }
        if plan.durationMinutes > Self.maxAnyDuration {
            return .needsShorterDuration(
                reason: "Workouts over \(Self.maxAnyDuration) minutes aren't recommended for a single session."
            )
        }

        let kcalPerMin = plan.durationMinutes > 0
            ? plan.estimatedCalories / Double(plan.durationMinutes)
            : 0
        if kcalPerMin > Self.maxKcalPerMinute {
            return .needsLowerIntensity(
                reason: "Calorie burn estimate looks unrealistic — try a lower intensity."
            )
        }

        // Back-to-back high-intensity check: if yesterday was already intense,
        // recommend dialing this one down rather than approving.
        if plan.intensity == .intense, didIntenseWorkoutWithinLastDay(input.recentSessions) {
            return .needsLowerIntensity(
                reason: "You did an intense workout recently — a moderate session helps recovery."
            )
        }

        // Soft warnings.
        var warnings: [String] = []

        let warmUp = plan.exercises
            .filter { $0.role == .warmUp }
            .reduce(0) { $0 + $1.durationMinutes }
        let cooldown = plan.exercises
            .filter { $0.role == .cooldown }
            .reduce(0) { $0 + $1.durationMinutes }

        if plan.durationMinutes >= 15 && warmUp < Self.recommendedWarmUpMinimum {
            warnings.append("Add a 3-5 minute warm-up before starting.")
        }
        if plan.durationMinutes >= 15 && cooldown < Self.recommendedCooldownMinimum {
            warnings.append("Finish with a 3-5 minute cooldown.")
        }
        if plan.intensity == .intense {
            warnings.append("Stop immediately if you feel pain, dizziness, or discomfort.")
        }
        warnings.append("This is general guidance, not medical advice.")

        return warnings.isEmpty ? .approved : .approvedWithWarnings(warnings)
    }

    private func didIntenseWorkoutWithinLastDay(_ sessions: [WorkoutSessionSummary]) -> Bool {
        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        return sessions.contains { $0.intensity == .intense && $0.date >= oneDayAgo }
    }
}
