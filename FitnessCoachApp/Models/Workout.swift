import Foundation

struct Workout: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var description: String
    var durationMinutes: Int
    var difficulty: Difficulty
    var exercises: [Exercise]
    var category: MuscleGroup

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        durationMinutes: Int,
        difficulty: Difficulty,
        exercises: [Exercise],
        category: MuscleGroup
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.durationMinutes = durationMinutes
        self.difficulty = difficulty
        self.exercises = exercises
        self.category = category
    }

    var totalSets: Int {
        return exercises.reduce(0) { $0 + $1.sets }
    }
}

enum Difficulty: String, CaseIterable, Codable, Identifiable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var id: String { return rawValue }

    var color: String {
        switch self {
        case .beginner: return "DifficultyBeginner"
        case .intermediate: return "DifficultyIntermediate"
        case .advanced: return "DifficultyAdvanced"
        }
    }

    var accentColorName: String {
        switch self {
        case .beginner: return "green"
        case .intermediate: return "orange"
        case .advanced: return "red"
        }
    }
}
