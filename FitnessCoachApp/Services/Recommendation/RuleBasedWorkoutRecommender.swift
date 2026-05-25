import Foundation

/// Rule-based recommendation engine.
///
/// Strategy:
///   1. Figure out the goal mode (recover vs. burn).
///   2. Ask the catalog for candidate exercises matching the mode.
///   3. Estimate calories for each candidate over the available time.
///   4. Score each candidate using the lesson's weighted formula.
///   5. Build a plan from the top candidate (with warm-up + cooldown).
///   6. Run the safety policy. If rejected, retry with adjusted inputs once.
///
/// No LLMs, no probabilistic anything — given the same input you get the same
/// output. That's the point.
struct RuleBasedWorkoutRecommender: WorkoutRecommending {

    let catalog: ExerciseCatalogProviding
    let estimator: CalorieEstimating
    let safety: WorkoutSafetyChecking

    init(catalog: ExerciseCatalogProviding,
         estimator: CalorieEstimating,
         safety: WorkoutSafetyChecking = DefaultSafetyPolicy()) {
        self.catalog = catalog
        self.estimator = estimator
        self.safety = safety
    }

    func recommendPlan(input: RecommendationInput) async throws -> WorkoutPlan {
        let plan = try await buildPlan(input: input)

        switch safety.validate(plan, input: input) {
        case .approved:
            return plan
        case .approvedWithWarnings(let warnings):
            var revised = plan
            revised.safetyNotes = warnings + plan.safetyNotes
            return revised

        case .needsLowerIntensity:
            // Re-try one notch lower.
            var retry = input
            retry.preferredIntensity = stepDown(input.preferredIntensity)
            let safer = try await buildPlan(input: retry)
            return tagWithWarnings(safer)

        case .needsShorterDuration:
            var retry = input
            retry.availableMinutes = max(10, input.availableMinutes / 2)
            let safer = try await buildPlan(input: retry)
            return tagWithWarnings(safer)
        }
    }

    // MARK: - Plan building

    private func buildPlan(input: RecommendationInput) async throws -> WorkoutPlan {
        let mode = goalMode(for: input)
        let candidates = try await fetchCandidates(for: mode, input: input)
        guard !candidates.isEmpty else { throw RecommendationError.noCandidates }

        let scored = await scored(candidates: candidates, input: input, mode: mode)
        guard let best = scored.first else { throw RecommendationError.noCandidates }

        return try await composePlan(from: best, input: input, mode: mode)
    }

    private func tagWithWarnings(_ plan: WorkoutPlan) -> WorkoutPlan {
        var p = plan
        switch safety.validate(p, input: RecommendationInput(
            targetCalories: 0, activeEnergyBurned: 0,
            availableMinutes: p.durationMinutes,
            preferredIntensity: p.intensity,
            bodyWeightPounds: nil, recentSessions: []
        )) {
        case .approvedWithWarnings(let warnings):
            p.safetyNotes = warnings + p.safetyNotes
        default: break
        }
        return p
    }

    // MARK: - Mode + queries

    private enum GoalMode { case recover, burn }

    private func goalMode(for input: RecommendationInput) -> GoalMode {
        input.remainingCalories <= 0 ? .recover : .burn
    }

    private func fetchCandidates(for mode: GoalMode,
                                 input: RecommendationInput) async throws -> [ExerciseTemplate] {
        switch mode {
        case .recover:
            // Goal already hit → suggest stretching or mobility.
            let stretching = try await catalog.fetchCandidates(
                query: .init(type: .stretching, muscle: nil, difficulty: .light, nameContains: nil)
            )
            let mobility = try await catalog.fetchCandidates(
                query: .init(type: .mobility, muscle: nil, difficulty: .light, nameContains: nil)
            )
            return stretching + mobility

        case .burn:
            // Match preferred intensity, but include adjacent ones so the
            // engine has room to pick. Strict difficulty filtering would
            // often leave us with too few options.
            let primary = try await catalog.fetchCandidates(
                query: .init(type: nil, muscle: nil,
                             difficulty: input.preferredIntensity, nameContains: nil)
            )
            // Pull in neighboring intensities too for variety.
            let neighbors = await neighborIntensityCandidates(of: input.preferredIntensity)
            return dedupedByID(primary + neighbors).filter { isWorkoutType($0.type) }
        }
    }

    private func neighborIntensityCandidates(of intensity: WorkoutIntensity) async -> [ExerciseTemplate] {
        let neighbors: [WorkoutIntensity]
        switch intensity {
        case .light: neighbors = [.moderate]
        case .moderate: neighbors = [.light, .intense]
        case .intense: neighbors = [.moderate]
        }
        var combined: [ExerciseTemplate] = []
        for n in neighbors {
            if let list = try? await catalog.fetchCandidates(
                query: .init(type: nil, muscle: nil, difficulty: n, nameContains: nil)
            ) {
                combined.append(contentsOf: list)
            }
        }
        return combined
    }

    private func isWorkoutType(_ type: ExerciseType) -> Bool {
        switch type {
        case .cardio, .strength, .plyometrics, .bodyweight: return true
        case .stretching, .mobility, .other: return false
        }
    }

    private func dedupedByID(_ list: [ExerciseTemplate]) -> [ExerciseTemplate] {
        var seen: Set<String> = []
        return list.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Scoring (slide 13)

    private struct ScoredCandidate {
        let exercise: ExerciseTemplate
        let estimate: CalorieEstimate
        let score: Double
    }

    private func scored(candidates: [ExerciseTemplate],
                        input: RecommendationInput,
                        mode: GoalMode) async -> [ScoredCandidate] {
        var result: [ScoredCandidate] = []
        for ex in candidates {
            guard let estimate = try? await estimator.estimateCalories(
                activityName: ex.name,
                weightPounds: input.bodyWeightPounds,
                durationMinutes: input.availableMinutes
            ) else { continue }

            let s = score(exercise: ex, estimate: estimate, input: input, mode: mode)
            result.append(.init(exercise: ex, estimate: estimate, score: s))
        }
        return result.sorted { $0.score > $1.score }
    }

    private func score(exercise: ExerciseTemplate,
                       estimate: CalorieEstimate,
                       input: RecommendationInput,
                       mode: GoalMode) -> Double {
        // weights from slide 13
        let calorieFit    = self.calorieFit(estimate.totalCalories, target: max(input.remainingCalories, 0), mode: mode)
        let durationFit   = self.durationFit(input.availableMinutes)
        let intensityFit  = self.intensityFit(exercise.difficulty, preferred: input.preferredIntensity)
        let noveltyFit    = self.noveltyFit(exercise, recent: input.recentSessions)
        let equipmentFit  = self.equipmentFit(exercise.equipment)
        let safetyPenalty = self.safetyPenalty(for: exercise, input: input)

        return calorieFit * 0.45
             + durationFit * 0.20
             + intensityFit * 0.20
             + noveltyFit * 0.10
             + equipmentFit * 0.05
             - safetyPenalty
    }

    private func calorieFit(_ estimated: Double, target: Double, mode: GoalMode) -> Double {
        if mode == .recover { return 1.0 } // calorie burn doesn't matter
        guard target > 0 else { return 0.5 }
        let diff = abs(estimated - target)
        // 1.0 when exact, falls off as |diff| grows. 0 once we're 200+ kcal away.
        return max(0, 1.0 - diff / 200.0)
    }

    private func durationFit(_ available: Int) -> Double {
        switch available {
        case ..<10:    return 0.3
        case 10..<20:  return 0.7
        case 20...45:  return 1.0
        case 46...75:  return 0.8
        default:       return 0.5
        }
    }

    private func intensityFit(_ actual: WorkoutIntensity,
                              preferred: WorkoutIntensity) -> Double {
        if actual == preferred { return 1.0 }
        // Adjacent intensities are partial credit.
        let distance = abs(actual.index - preferred.index)
        return distance == 1 ? 0.5 : 0.2
    }

    private func noveltyFit(_ exercise: ExerciseTemplate,
                            recent: [WorkoutSessionSummary]) -> Double {
        // Penalize titles that appeared in the last week.
        let lower = exercise.name.lowercased()
        let recentMatches = recent.filter {
            $0.title.lowercased().contains(lower) || lower.contains($0.title.lowercased())
        }
        if recentMatches.isEmpty { return 1.0 }
        return max(0, 1.0 - 0.3 * Double(recentMatches.count))
    }

    private func equipmentFit(_ equipment: [String]) -> Double {
        // No-equipment options score highest by default — we don't know what
        // the user has at home. The lesson lists equipment as a 5% nudge.
        equipment.isEmpty ? 1.0 : 0.6
    }

    private func safetyPenalty(for exercise: ExerciseTemplate,
                               input: RecommendationInput) -> Double {
        var penalty = 0.0
        if exercise.difficulty == .intense, input.availableMinutes > 45 {
            penalty += 0.3
        }
        if exercise.difficulty == .intense,
           input.recentSessions.contains(where: { $0.intensity == .intense }) {
            penalty += 0.2
        }
        return penalty
    }

    // MARK: - Plan composition

    private func composePlan(from best: ScoredCandidate,
                             input: RecommendationInput,
                             mode: GoalMode) async throws -> WorkoutPlan {
        let totalMinutes = max(input.availableMinutes, 5)

        // Always reserve warm-up + cooldown when duration allows (slide 31).
        let includesWarmup = totalMinutes >= 15
        let warmUpMinutes = includesWarmup ? max(3, totalMinutes / 10) : 0
        let cooldownMinutes = includesWarmup ? max(3, totalMinutes / 10) : 0
        let mainMinutes = max(5, totalMinutes - warmUpMinutes - cooldownMinutes)

        let mainEstimate = try await estimator.estimateCalories(
            activityName: best.exercise.name,
            weightPounds: input.bodyWeightPounds,
            durationMinutes: mainMinutes
        )

        var blocks: [ExerciseBlock] = []
        if warmUpMinutes > 0 {
            let warmUpEst = (try? await estimator.estimateCalories(
                activityName: "Jumping Jacks",
                weightPounds: input.bodyWeightPounds,
                durationMinutes: warmUpMinutes
            ))?.totalCalories ?? 0
            blocks.append(.init(
                name: "Light Warm-up",
                durationMinutes: warmUpMinutes,
                estimatedCalories: warmUpEst,
                role: .warmUp,
                instructions: "Easy movement to raise your heart rate. Arm circles, light jog in place, jumping jacks.",
                primaryMuscle: "full body"
            ))
        }

        blocks.append(.init(
            name: best.exercise.name,
            durationMinutes: mainMinutes,
            estimatedCalories: mainEstimate.totalCalories,
            role: .main,
            instructions: best.exercise.instructions,
            primaryMuscle: best.exercise.primaryMuscle
        ))

        if cooldownMinutes > 0 {
            let cooldownEst = (try? await estimator.estimateCalories(
                activityName: "Stretching",
                weightPounds: input.bodyWeightPounds,
                durationMinutes: cooldownMinutes
            ))?.totalCalories ?? 0
            blocks.append(.init(
                name: "Cooldown Stretch",
                durationMinutes: cooldownMinutes,
                estimatedCalories: cooldownEst,
                role: .cooldown,
                instructions: "Slow stretches for the muscles you just worked. Hold 20-30s each.",
                primaryMuscle: best.exercise.primaryMuscle
            ))
        }

        let totalKcal = blocks.reduce(0.0) { $0 + $1.estimatedCalories }
        let title = mode == .recover
            ? "Recovery & Mobility"
            : "\(best.exercise.name) — \(input.preferredIntensity.displayName)"

        var safetyNotes: [String] = []
        if let info = best.exercise.safetyInfo { safetyNotes.append(info) }

        return WorkoutPlan(
            title: title,
            estimatedCalories: totalKcal.rounded(),
            durationMinutes: totalMinutes,
            intensity: best.exercise.difficulty,
            exercises: blocks,
            sourceProvider: best.exercise.sourceProvider,
            safetyNotes: safetyNotes
        )
    }

    private func stepDown(_ intensity: WorkoutIntensity) -> WorkoutIntensity {
        switch intensity {
        case .intense: return .moderate
        case .moderate: return .light
        case .light: return .light
        }
    }
}

private extension WorkoutIntensity {
    var index: Int {
        switch self {
        case .light: return 0
        case .moderate: return 1
        case .intense: return 2
        }
    }
}
