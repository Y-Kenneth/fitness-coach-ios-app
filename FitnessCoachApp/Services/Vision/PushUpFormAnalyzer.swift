import Foundation

// MARK: - Rep counter

final class PushUpCounter {
    private enum Phase { case up, down }
    private var phase: Phase = .up
    private(set) var count = 0

    // Hysteresis: arms must fully bend then fully extend to count one rep.
    private let downAngle: Double = 95.0   // elbows must go BELOW this to register "down"
    private let upAngle:   Double = 150.0  // must extend ABOVE this to complete the rep

    func update(elbowAngle: Double?) {
        guard let angle = elbowAngle else { return }
        switch phase {
        case .up   where angle < downAngle: phase = .down
        case .down where angle > upAngle:   phase = .up; count += 1
        default: break
        }
    }

    func reset() { count = 0; phase = .up }
}

// MARK: - Form analyzer

struct PushUpFormAnalyzer: FormAnalyzer {

    struct Thresholds {
        /// Elbow angle threshold: if elbows are bending but stay above this, depth is insufficient.
        var minDepthElbowAngle: Double = 108.0
        /// Hip sag limit (normalized). Below this = sagging.
        var maxHipSag:   Double = -0.055
        /// Hip pike limit (normalized). Above this = piking.
        var maxHipPike:  Double =  0.065
        /// Elbow spread / shoulder width. Above this = flared elbows.
        var maxElbowSpreadRatio: Double = 1.55
    }

    var thresholds = Thresholds()

    func analyze(features: PoseFeatures) -> FormFeedback {
        if !features.bodyFullyVisible { return .bodyNotFullyVisible }
        if features.lowConfidence     { return .lowConfidence }

        // Body alignment is a structural fault — check first.
        if let sag = features.hipSagOffset {
            if sag < thresholds.maxHipSag  { return .hipsSagging }
            if sag > thresholds.maxHipPike { return .hipsRaised  }
        }

        // Elbow flare — structural fault if severe.
        if let spread = features.elbowSpreadRatio,
           spread > thresholds.maxElbowSpreadRatio {
            return .elbowsTooWide
        }

        // Depth — only critique when actually mid-rep (elbows actively bending).
        if let elbow = features.elbowAngleDegrees,
           elbow < 150,
           elbow > thresholds.minDepthElbowAngle {
            return .pushUpNotLowEnough
        }

        return .goodForm
    }
}
