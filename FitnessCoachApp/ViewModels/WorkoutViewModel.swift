import SwiftUI
import Combine

@MainActor
final class WorkoutViewModel: ObservableObject {
    @Published private(set) var workouts: [Workout] = []
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published var selectedFilter: MuscleGroup? = nil
    @Published var isSessionActive = false
    @Published var activeWorkout: Workout? = nil
    @Published var sessionElapsedSeconds: Int = 0

    private var timerCancellable: AnyCancellable?
    private let sessionsKey = "fitness.sessions"
    let healthProvider: any HealthDataProvider

    init() {
        #if targetEnvironment(simulator)
        self.healthProvider = MockHealthDataProvider()
        #else
        self.healthProvider = LiveHealthDataProvider()
        #endif
        workouts = Self.makeSampleWorkouts()
        loadSessions()
    }

    var filteredWorkouts: [Workout] {
        guard let filter = selectedFilter else { return workouts }
        return workouts.filter { $0.category == filter }
    }

    var totalWorkoutsThisWeek: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date.now)?.start ?? Date.now
        return sessions.filter { $0.date >= startOfWeek }.count
    }

    var totalCaloriesThisWeek: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date.now)?.start ?? Date.now
        return sessions
            .filter { $0.date >= startOfWeek }
            .reduce(0) { $0 + $1.caloriesBurned }
    }

    var totalMinutesThisWeek: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date.now)?.start ?? Date.now
        return sessions
            .filter { $0.date >= startOfWeek }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    func weeklyActivityData() -> [(String, Int)] {
        let calendar = Calendar.current
        let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return weekdays.enumerated().map { index, label in
            // Calendar weekday: 1=Sun, 2=Mon ... 7=Sat; index 0=Mon maps to weekday 2
            let targetWeekday = index + 2 > 7 ? index + 2 - 7 : index + 2
            let count = sessions.filter { session in
                calendar.component(.weekday, from: session.date) == targetWeekday
            }.count
            return (label, count)
        }
    }

    func startSession(for workout: Workout) {
        activeWorkout = workout
        isSessionActive = true
        sessionElapsedSeconds = 0
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sessionElapsedSeconds += 1
            }
    }

    func finishSession() {
        guard let workout = activeWorkout else { return }
        timerCancellable?.cancel()
        timerCancellable = nil

        let minutes = max(1, sessionElapsedSeconds / 60)
        let calories = Int(Double(minutes) * 7.5)
        let session = WorkoutSession(
            workoutID: workout.id,
            workoutName: workout.name,
            durationMinutes: minutes,
            caloriesBurned: calories
        )
        sessions.insert(session, at: 0)
        saveSessions()

        let kcal = Double(calories)
        let date = Date()
        Task {
            try? await healthProvider.writeWorkoutCalories(kcal, date: date)
        }

        isSessionActive = false
        activeWorkout = nil
        sessionElapsedSeconds = 0
    }

    func cancelSession() {
        timerCancellable?.cancel()
        timerCancellable = nil
        isSessionActive = false
        activeWorkout = nil
        sessionElapsedSeconds = 0
    }

    private func saveSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: sessionsKey)
    }

    private func loadSessions() {
        guard
            let data = UserDefaults.standard.data(forKey: sessionsKey),
            let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data)
        else { return }
        sessions = decoded
    }

    private static func makeSampleWorkouts() -> [Workout] {
        [
            Workout(
                name: "Push Day Power",
                description: "A classic chest, shoulders and triceps session to build upper body strength.",
                durationMinutes: 50,
                difficulty: .intermediate,
                exercises: [
                    Exercise(name: "Bench Press", sets: 4, reps: 8, weightKg: 60, muscleGroup: .chest),
                    Exercise(name: "Incline Dumbbell Press", sets: 3, reps: 10, weightKg: 22, muscleGroup: .chest),
                    Exercise(name: "Overhead Press", sets: 4, reps: 8, weightKg: 40, muscleGroup: .shoulders),
                    Exercise(name: "Lateral Raises", sets: 3, reps: 15, weightKg: 8, muscleGroup: .shoulders),
                    Exercise(name: "Tricep Pushdown", sets: 3, reps: 12, weightKg: 20, muscleGroup: .arms),
                ],
                category: .chest
            ),
            Workout(
                name: "Pull Day Strength",
                description: "Target your back and biceps with heavy compound lifts.",
                durationMinutes: 55,
                difficulty: .intermediate,
                exercises: [
                    Exercise(name: "Deadlift", sets: 4, reps: 5, weightKg: 100, muscleGroup: .back),
                    Exercise(name: "Pull-ups", sets: 4, reps: 8, weightKg: 0, muscleGroup: .back),
                    Exercise(name: "Barbell Row", sets: 4, reps: 8, weightKg: 60, muscleGroup: .back),
                    Exercise(name: "Face Pulls", sets: 3, reps: 15, weightKg: 15, muscleGroup: .shoulders),
                    Exercise(name: "Barbell Curl", sets: 3, reps: 12, weightKg: 30, muscleGroup: .arms),
                ],
                category: .back
            ),
            Workout(
                name: "Leg Day Blast",
                description: "Build powerful legs and glutes with squats and lunges.",
                durationMinutes: 60,
                difficulty: .advanced,
                exercises: [
                    Exercise(name: "Barbell Squat", sets: 5, reps: 5, weightKg: 80, muscleGroup: .legs),
                    Exercise(name: "Romanian Deadlift", sets: 4, reps: 10, weightKg: 60, muscleGroup: .legs),
                    Exercise(name: "Leg Press", sets: 4, reps: 12, weightKg: 120, muscleGroup: .legs),
                    Exercise(name: "Walking Lunges", sets: 3, reps: 20, weightKg: 20, muscleGroup: .legs),
                    Exercise(name: "Calf Raises", sets: 4, reps: 20, weightKg: 40, muscleGroup: .legs),
                ],
                category: .legs
            ),
            Workout(
                name: "Core & Cardio Burn",
                description: "A high-intensity core circuit combined with cardio intervals.",
                durationMinutes: 35,
                difficulty: .beginner,
                exercises: [
                    Exercise(name: "Plank", sets: 4, reps: 1, muscleGroup: .core, notes: "Hold 60s each"),
                    Exercise(name: "Bicycle Crunches", sets: 3, reps: 20, muscleGroup: .core),
                    Exercise(name: "Mountain Climbers", sets: 4, reps: 30, muscleGroup: .cardio),
                    Exercise(name: "Russian Twists", sets: 3, reps: 20, weightKg: 5, muscleGroup: .core),
                    Exercise(name: "Burpees", sets: 3, reps: 10, muscleGroup: .cardio),
                ],
                category: .core
            ),
            Workout(
                name: "Full Body HIIT",
                description: "Burn fat and build endurance with this total-body HIIT circuit.",
                durationMinutes: 30,
                difficulty: .intermediate,
                exercises: [
                    Exercise(name: "Jump Squats", sets: 4, reps: 15, muscleGroup: .legs),
                    Exercise(name: "Push-ups", sets: 4, reps: 15, muscleGroup: .chest),
                    Exercise(name: "Kettlebell Swings", sets: 4, reps: 20, weightKg: 16, muscleGroup: .fullBody),
                    Exercise(name: "Box Jumps", sets: 3, reps: 10, muscleGroup: .legs),
                    Exercise(name: "Dumbbell Thrusters", sets: 3, reps: 12, weightKg: 14, muscleGroup: .fullBody),
                ],
                category: .fullBody
            ),
            Workout(
                name: "Beginner Foundations",
                description: "Perfect for those just starting out. Build strength and confidence.",
                durationMinutes: 40,
                difficulty: .beginner,
                exercises: [
                    Exercise(name: "Goblet Squat", sets: 3, reps: 12, weightKg: 8, muscleGroup: .legs),
                    Exercise(name: "Dumbbell Row", sets: 3, reps: 12, weightKg: 10, muscleGroup: .back),
                    Exercise(name: "Dumbbell Press", sets: 3, reps: 12, weightKg: 10, muscleGroup: .chest),
                    Exercise(name: "Hip Bridge", sets: 3, reps: 15, muscleGroup: .legs),
                    Exercise(name: "Dead Bug", sets: 3, reps: 10, muscleGroup: .core),
                ],
                category: .fullBody
            ),
        ]
    }
}
