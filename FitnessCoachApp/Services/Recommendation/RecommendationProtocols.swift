import Foundation

// MARK: - Exercise catalog

struct ExerciseSearchQuery: Hashable {
    var type: ExerciseType?
    var muscle: String?
    var difficulty: WorkoutIntensity?
    var nameContains: String?
}

protocol ExerciseCatalogProviding {
    func fetchCandidates(query: ExerciseSearchQuery) async throws -> [ExerciseTemplate]
}

// MARK: - Calorie estimates

struct CalorieEstimate: Codable, Hashable {
    var totalCalories: Double
    var caloriesPerHour: Double
    var sourceProvider: String
}

protocol CalorieEstimating {
    func estimateCalories(
        activityName: String,
        weightPounds: Double?,
        durationMinutes: Int
    ) async throws -> CalorieEstimate
}

// MARK: - Recommendation engine

protocol WorkoutRecommending {
    func recommendPlan(input: RecommendationInput) async throws -> WorkoutPlan
}

// MARK: - Safety policy

enum SafetyResult: Equatable {
    case approved
    case approvedWithWarnings([String])
    case needsLowerIntensity(reason: String)
    case needsShorterDuration(reason: String)

    var isApproved: Bool {
        switch self {
        case .approved, .approvedWithWarnings: return true
        case .needsLowerIntensity, .needsShorterDuration: return false
        }
    }

    var warnings: [String] {
        if case .approvedWithWarnings(let list) = self { return list }
        return []
    }
}

protocol WorkoutSafetyChecking {
    func validate(_ plan: WorkoutPlan, input: RecommendationInput) -> SafetyResult
}

// MARK: - Engine errors

enum RecommendationError: LocalizedError {
    case noCandidates
    case allCandidatesUnsafe
    case providerFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noCandidates:
            return "No exercise candidates could be found right now."
        case .allCandidatesUnsafe:
            return "Every candidate plan failed the safety check."
        case .providerFailed(let underlying):
            return "Exercise provider failed: \(underlying.localizedDescription)"
        }
    }
}
