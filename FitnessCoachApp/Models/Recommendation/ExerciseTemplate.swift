import Foundation

/// One exercise as it appears in our normalized internal model.
/// External API schemas (API Ninjas, ExerciseDB) are mapped onto this shape
/// so the rest of the app never sees provider-specific JSON.
struct ExerciseTemplate: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var type: ExerciseType
    var difficulty: WorkoutIntensity
    var primaryMuscle: String?
    var equipment: [String]
    var instructions: String
    var safetyInfo: String?
    var sourceProvider: String
}

enum ExerciseType: String, Codable, Hashable, CaseIterable {
    case cardio
    case strength
    case stretching
    case mobility
    case plyometrics
    case bodyweight
    case other

    /// Map an API Ninjas type string onto our enum.
    static func fromAPIType(_ raw: String?) -> ExerciseType {
        switch (raw ?? "").lowercased() {
        case "cardio": return .cardio
        case "strength", "strongman", "powerlifting", "olympic_weightlifting":
            return .strength
        case "stretching": return .stretching
        case "plyometrics": return .plyometrics
        default:
            return .other
        }
    }
}
