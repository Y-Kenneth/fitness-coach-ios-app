import Foundation

enum DetectedExercise: String, Equatable, Hashable {
    case squat  = "Squat"
    case pushUp = "Push-Up"
    case lunge  = "Lunge"
    case unknown

    var repLabel: String {
        switch self {
        case .squat:   return "SQUATS"
        case .pushUp:  return "PUSH-UPS"
        case .lunge:   return "LUNGES"
        case .unknown: return "REPS"
        }
    }

    var displayName: String {
        switch self {
        case .squat:   return "SQUAT"
        case .pushUp:  return "PUSH-UP"
        case .lunge:   return "LUNGE"
        case .unknown: return "DETECTING…"
        }
    }

    /// Estimated kcal burned per rep for an average adult.
    var caloriesPerRep: Double {
        switch self {
        case .squat:   return 0.50
        case .pushUp:  return 0.35
        case .lunge:   return 0.60
        case .unknown: return 0
        }
    }

    var systemImage: String {
        switch self {
        case .squat:   return "figure.stand"
        case .pushUp:  return "figure.arms.open"
        case .lunge:   return "figure.walk"
        case .unknown: return "camera.viewfinder"
        }
    }
}

/// Classifies the current exercise from pose features with temporal smoothing.
///
/// Raw per-frame classification would flicker because the user is always
/// transitioning between poses. A sliding window vote with a switch threshold
/// (~0.5 s) prevents false triggers while still responding quickly to a
/// genuine exercise change.
final class ExerciseDetector {

    private var history: [DetectedExercise] = []
    private let windowSize = 24       // ~0.8 s at 30 fps
    private let switchThreshold = 15  // need 15/24 consistent frames to switch

    private(set) var current: DetectedExercise = .unknown

    func update(features: PoseFeatures) -> DetectedExercise {
        let raw = classify(features)
        history.append(raw)
        if history.count > windowSize { history.removeFirst() }

        var votes: [DetectedExercise: Int] = [:]
        history.forEach { votes[$0, default: 0] += 1 }

        if let winner = votes.max(by: { $0.value < $1.value }),
           winner.value >= switchThreshold,
           winner.key != current {
            current = winner.key
        }
        return current
    }

    func reset() {
        history.removeAll()
        current = .unknown
    }

    // MARK: - Rule-based single-frame classification

    private func classify(_ f: PoseFeatures) -> DetectedExercise {
        guard !f.lowConfidence, f.bodyFullyVisible else { return .unknown }

        // Push-up: spine nearly horizontal (body prone on ground).
        // spineAngleDeg is 0° upright → 90° horizontal.
        // Threshold is 65° (not 52°) so a torso-lean squat (~40-60°) doesn't
        // get misclassified as a push-up, which would crash the exercise state machine.
        if let spineAngle = f.spineAngleDeg, spineAngle > 65 {
            return .pushUp
        }

        // Lunge: upright posture + pronounced knee angle asymmetry.
        // In a squat both knees bend together; in a lunge one knee is at ~90°
        // while the other is near 120-140°, giving a difference > 30°.
        if let diff = f.kneeAngleDiffDeg, diff > 30 {
            return .lunge
        }

        // Default: squat (upright + symmetric knee angles).
        return .squat
    }
}
