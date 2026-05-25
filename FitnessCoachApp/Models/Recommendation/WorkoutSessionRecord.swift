import Foundation

/// One completed workout session, persisted to disk as JSON.
/// (Originally written for SwiftData; downgraded to a plain Codable so we can
/// keep the iOS deployment target at 16.4.)
struct WorkoutSessionRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var title: String
    var estimatedCalories: Double
    var durationMinutes: Int
    var intensity: WorkoutIntensity
    var completed: Bool

    func toSummary() -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            date: date,
            title: title,
            intensity: intensity,
            durationMinutes: durationMinutes
        )
    }
}
