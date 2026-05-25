import Foundation

enum WorkoutIntensity: String, Codable, CaseIterable, Identifiable, Hashable {
    case light
    case moderate
    case intense

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .intense: return "Intense"
        }
    }

    var emoji: String {
        switch self {
        case .light: return "🌱"
        case .moderate: return "🔥"
        case .intense: return "⚡️"
        }
    }

    /// Multiplier on the baseline calorie estimate. Used by mock estimators
    /// and as a sanity check on API estimates.
    var calorieMultiplier: Double {
        switch self {
        case .light: return 0.8
        case .moderate: return 1.0
        case .intense: return 1.25
        }
    }

    /// Maps an API Ninjas difficulty string ("beginner"/"intermediate"/"expert")
    /// to our internal intensity enum.
    static func fromAPIDifficulty(_ raw: String?) -> WorkoutIntensity {
        switch (raw ?? "").lowercased() {
        case "beginner": return .light
        case "expert": return .intense
        default: return .moderate
        }
    }
}
