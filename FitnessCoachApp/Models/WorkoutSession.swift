import Foundation

struct WorkoutSession: Identifiable, Codable {
    let id: UUID
    let workoutID: UUID
    let workoutName: String
    let date: Date
    let durationMinutes: Int
    let caloriesBurned: Int

    init(
        id: UUID = UUID(),
        workoutID: UUID,
        workoutName: String,
        date: Date = Date.now,
        durationMinutes: Int,
        caloriesBurned: Int
    ) {
        self.id = id
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.date = date
        self.durationMinutes = durationMinutes
        self.caloriesBurned = caloriesBurned
    }
}
