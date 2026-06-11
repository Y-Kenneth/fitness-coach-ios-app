import Foundation

// MARK: - Rep counter

final class LungeCounter {
    private enum Phase { case up, down }
    private var phase: Phase = .up
    private(set) var count = 0

    // In a lunge, the average knee angle (both legs) reaches ~100° at the bottom
    // and ~160°+ at the top. Hysteresis prevents noise near the thresholds.
    private let downAngle: Double = 103.0
    private let upAngle:   Double = 158.0

    func update(kneeAngle: Double?) {
        guard let angle = kneeAngle else { return }
        switch phase {
        case .up   where angle < downAngle: phase = .down
        case .down where angle > upAngle:   phase = .up; count += 1
        default: break
        }
    }

    func reset() { count = 0; phase = .up }
}

// MARK: - Form analyzer

struct LungeFormAnalyzer: FormAnalyzer {

    struct Thresholds {
        /// Below this average knee angle the lunge is considered deep enough.
        var deepEnoughKneeAngle: Double = 108.0
        /// Above this spine angle from vertical = forward lean fault.
        var maxSpineLean: Double = 18.0
        /// Normalized horizontal knee-ankle offset: large value = knee tracking past toes.
        var maxKneeForwardDrift: Double = 0.075
        /// Average knee angle above which the user is standing between reps.
        var standingKneeAngle: Double = 155.0
    }

    var thresholds = Thresholds()

    func analyze(features: PoseFeatures) -> FormFeedback {
        if !features.bodyFullyVisible { return .bodyNotFullyVisible }
        if features.lowConfidence     { return .lowConfidence }

        guard let knee = features.kneeAngleDegrees else { return .bodyNotFullyVisible }

        // Between reps (standing upright) — no critique needed.
        if knee >= thresholds.standingKneeAngle { return .goodForm }

        // Torso lean is a structural fault — check before alignment/depth.
        if let spine = features.spineAngleDeg, spine > thresholds.maxSpineLean {
            return .lungeForwardLean
        }

        // Front knee tracking past toes (uses kneeAnkleDrift proxy from features).
        if let drift = features.kneeAnkleDriftNormalized,
           drift > thresholds.maxKneeForwardDrift {
            return .lungeKneeForward
        }

        // Depth: front knee should reach ~90°; averaged with back knee ~90° means average ~95-100°.
        if knee > thresholds.deepEnoughKneeAngle {
            return .lungeNotDeepEnough
        }

        return .goodForm
    }
}
