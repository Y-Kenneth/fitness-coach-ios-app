import Foundation

struct Exercise: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var sets: Int
    var reps: Int
    var weightKg: Double
    var muscleGroup: MuscleGroup
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        sets: Int,
        reps: Int,
        weightKg: Double = 0,
        muscleGroup: MuscleGroup,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weightKg = weightKg
        self.muscleGroup = muscleGroup
        self.notes = notes
    }
}

enum MuscleGroup: String, CaseIterable, Codable, Identifiable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case core = "Core"
    case legs = "Legs"
    case cardio = "Cardio"
    case fullBody = "Full Body"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rowing"
        case .shoulders: return "figure.mixed.cardio"
        case .arms: return "figure.strengthtraining.functional"
        case .core: return "figure.core.training"
        case .legs: return "figure.run"
        case .cardio: return "heart.fill"
        case .fullBody: return "figure.flexibility"
        }
    }
}
