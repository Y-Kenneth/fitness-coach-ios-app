import Foundation

/// Tries `primary` first and falls back to `secondary` if the call throws.
/// Logs the failure so we can see in the console when we're degraded.
struct FallbackExerciseCatalog: ExerciseCatalogProviding {
    let primary: ExerciseCatalogProviding
    let secondary: ExerciseCatalogProviding

    func fetchCandidates(query: ExerciseSearchQuery) async throws -> [ExerciseTemplate] {
        do {
            let result = try await primary.fetchCandidates(query: query)
            if result.isEmpty {
                print("ℹ️ Primary exercise catalog returned empty — using fallback.")
                return try await secondary.fetchCandidates(query: query)
            }
            return result
        } catch {
            print("⚠️ Primary exercise catalog failed (\(error.localizedDescription)) — using fallback.")
            return try await secondary.fetchCandidates(query: query)
        }
    }
}

struct FallbackCalorieEstimator: CalorieEstimating {
    let primary: CalorieEstimating
    let secondary: CalorieEstimating

    func estimateCalories(activityName: String,
                          weightPounds: Double?,
                          durationMinutes: Int) async throws -> CalorieEstimate {
        do {
            return try await primary.estimateCalories(
                activityName: activityName,
                weightPounds: weightPounds,
                durationMinutes: durationMinutes
            )
        } catch {
            print("⚠️ Primary calorie estimator failed (\(error.localizedDescription)) — using MET fallback.")
            return try await secondary.estimateCalories(
                activityName: activityName,
                weightPounds: weightPounds,
                durationMinutes: durationMinutes
            )
        }
    }
}

/// Convenience factory that returns the recommended composition: real APIs
/// with mock fallback. Use this everywhere except specific unit-test setups.
enum RecommendationFactory {
    static func makeEngine() -> WorkoutRecommending {
        let catalog = FallbackExerciseCatalog(
            primary: APINinjasExerciseCatalog(),
            secondary: MockExerciseCatalog()
        )
        let estimator = FallbackCalorieEstimator(
            primary: APINinjasCalorieEstimator(),
            secondary: MockCalorieEstimator()
        )
        return RuleBasedWorkoutRecommender(
            catalog: catalog,
            estimator: estimator,
            safety: DefaultSafetyPolicy()
        )
    }

    /// Pure-mock engine for SwiftUI previews and unit tests.
    static func makeMockEngine() -> WorkoutRecommending {
        RuleBasedWorkoutRecommender(
            catalog: MockExerciseCatalog(),
            estimator: MockCalorieEstimator(),
            safety: DefaultSafetyPolicy()
        )
    }

    /// Returns the live media provider when a RapidAPI key is configured,
    /// otherwise a no-op so the UI gracefully omits the GIFs.
    static func makeMediaProvider() -> ExerciseMediaProviding {
        Secrets.rapidAPIKey.isEmpty
            ? NoMediaProvider()
            : ExerciseDBMediaProvider()
    }
}
