import Foundation

/// Hardcoded exercise list for previews, tests, and offline fallback.
/// Picked to give the engine enough variety across types, intensities, and
/// muscle groups for the scoring formula to do something meaningful.
struct MockExerciseCatalog: ExerciseCatalogProviding {

    static let library: [ExerciseTemplate] = [
        // Cardio (light)
        .init(id: "walk-brisk", name: "Brisk Walking", type: .cardio,
              difficulty: .light, primaryMuscle: "legs", equipment: [],
              instructions: "Walk at a pace where you can still hold a conversation.",
              safetyInfo: "Stop if you feel dizzy or short of breath.",
              sourceProvider: "mock"),

        .init(id: "cycle-easy", name: "Easy Cycling", type: .cardio,
              difficulty: .light, primaryMuscle: "legs", equipment: ["bike"],
              instructions: "Cycle on flat ground or a stationary bike at moderate effort.",
              safetyInfo: "Adjust seat height to avoid knee strain.",
              sourceProvider: "mock"),

        // Cardio (moderate)
        .init(id: "jog", name: "Jogging", type: .cardio,
              difficulty: .moderate, primaryMuscle: "legs", equipment: [],
              instructions: "Maintain a steady jog. Land mid-foot and stay relaxed.",
              safetyInfo: "Warm up first. Stop on knee or shin pain.",
              sourceProvider: "mock"),

        .init(id: "rowing", name: "Rowing", type: .cardio,
              difficulty: .moderate, primaryMuscle: "back", equipment: ["rower"],
              instructions: "Drive with the legs first, then pull with the arms.",
              safetyInfo: "Keep a neutral spine; don't round your back.",
              sourceProvider: "mock"),

        // Cardio (intense)
        .init(id: "hiit-sprints", name: "Sprint Intervals", type: .cardio,
              difficulty: .intense, primaryMuscle: "legs", equipment: [],
              instructions: "Sprint 30s, walk 60s, repeat for the duration.",
              safetyInfo: "Stop if you feel pain. Cool down for at least 5 minutes.",
              sourceProvider: "mock"),

        // Bodyweight strength
        .init(id: "pushups", name: "Push-ups", type: .bodyweight,
              difficulty: .moderate, primaryMuscle: "chest", equipment: [],
              instructions: "Keep your body in a straight line. Lower until elbows are at 90°.",
              safetyInfo: "Drop to knees if your form breaks.",
              sourceProvider: "mock"),

        .init(id: "squats-bodyweight", name: "Bodyweight Squats",
              type: .bodyweight, difficulty: .light, primaryMuscle: "quadriceps",
              equipment: [],
              instructions: "Feet shoulder-width apart. Sit back as if into a chair.",
              safetyInfo: "Don't let knees cave inward.",
              sourceProvider: "mock"),

        .init(id: "lunges", name: "Walking Lunges", type: .bodyweight,
              difficulty: .moderate, primaryMuscle: "legs", equipment: [],
              instructions: "Step forward into a lunge, then alternate legs.",
              safetyInfo: "Stop if you feel sharp knee pain.",
              sourceProvider: "mock"),

        .init(id: "plank", name: "Plank Hold", type: .bodyweight,
              difficulty: .moderate, primaryMuscle: "core", equipment: [],
              instructions: "Hold a straight body line from head to heels.",
              safetyInfo: "Don't let hips sag.",
              sourceProvider: "mock"),

        // Plyometrics
        .init(id: "jumping-jacks", name: "Jumping Jacks", type: .plyometrics,
              difficulty: .light, primaryMuscle: "full body", equipment: [],
              instructions: "Jump while spreading arms and legs. Continuous rhythm.",
              safetyInfo: "Land softly. Skip if you have knee issues.",
              sourceProvider: "mock"),

        .init(id: "burpees", name: "Burpees", type: .plyometrics,
              difficulty: .intense, primaryMuscle: "full body", equipment: [],
              instructions: "Squat, kick legs back to plank, hop back in, jump up.",
              safetyInfo: "Very high impact. Stop on dizziness.",
              sourceProvider: "mock"),

        .init(id: "mountain-climbers", name: "Mountain Climbers",
              type: .plyometrics, difficulty: .moderate, primaryMuscle: "core",
              equipment: [],
              instructions: "From a plank, drive knees toward chest alternately.",
              safetyInfo: "Keep hips low.",
              sourceProvider: "mock"),

        // Stretching / mobility (used when goal already reached)
        .init(id: "yoga-flow", name: "Gentle Yoga Flow", type: .stretching,
              difficulty: .light, primaryMuscle: "full body", equipment: ["mat"],
              instructions: "Move slowly through cat-cow, downward dog, and child's pose.",
              safetyInfo: "Breathe deeply. Never force a stretch.",
              sourceProvider: "mock"),

        .init(id: "foam-rolling", name: "Foam Rolling", type: .mobility,
              difficulty: .light, primaryMuscle: "legs", equipment: ["foam roller"],
              instructions: "Roll slowly over tight muscles for 30-60s each.",
              safetyInfo: "Avoid rolling directly on joints.",
              sourceProvider: "mock"),

        .init(id: "stretch-hamstring", name: "Hamstring Stretch",
              type: .stretching, difficulty: .light, primaryMuscle: "hamstrings",
              equipment: [],
              instructions: "Sit with one leg extended; reach for the toes.",
              safetyInfo: "Hold for 30 seconds without bouncing.",
              sourceProvider: "mock"),
    ]

    func fetchCandidates(query: ExerciseSearchQuery) async throws -> [ExerciseTemplate] {
        Self.library.filter { match($0, query: query) }
    }

    private func match(_ ex: ExerciseTemplate, query: ExerciseSearchQuery) -> Bool {
        if let t = query.type, ex.type != t { return false }
        if let m = query.muscle?.lowercased(),
           !(ex.primaryMuscle?.lowercased() ?? "").contains(m) { return false }
        if let d = query.difficulty, ex.difficulty != d { return false }
        if let n = query.nameContains?.lowercased(), !n.isEmpty,
           !ex.name.lowercased().contains(n) { return false }
        return true
    }
}
