import Foundation

/// One step inside a recommended plan — e.g. "5 min jumping jacks warm-up".
struct ExerciseBlock: Identifiable, Codable, Hashable {
    var id: String { "\(name)-\(durationMinutes)-\(role.rawValue)" }
    var name: String
    var durationMinutes: Int
    var estimatedCalories: Double
    var role: BlockRole
    var instructions: String?
    var primaryMuscle: String?
}

enum BlockRole: String, Codable, Hashable {
    case warmUp
    case main
    case cooldown

    var displayName: String {
        switch self {
        case .warmUp: return "Warm-up"
        case .main: return "Main"
        case .cooldown: return "Cooldown"
        }
    }
}

/// The final output the engine returns to the UI.
struct WorkoutPlan: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var estimatedCalories: Double
    var durationMinutes: Int
    var intensity: WorkoutIntensity
    var exercises: [ExerciseBlock]
    var sourceProvider: String
    var safetyNotes: [String]
    var createdAt: Date = Date()
}
