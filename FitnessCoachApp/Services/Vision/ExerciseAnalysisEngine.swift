import Foundation
import Vision

struct ExerciseAnalysisResult {
    let exercise: DetectedExercise
    let feedback: FormFeedback
    let repCount: Int
    let viewpoint: Viewpoint
}

/// Single entry point that:
///   1. Detects which exercise the user is performing (with temporal smoothing).
///   2. Routes joints → PoseFeatures → the appropriate form analyzer.
///   3. Counts reps with the matching counter.
///   4. Resets counters automatically when the detected exercise changes.
final class ExerciseAnalysisEngine {

    private let detector         = ExerciseDetector()
    private let squatMLClassifier = SquatMLClassifier()
    private let pushUpAnalyzer   = PushUpFormAnalyzer()
    private let lungeAnalyzer    = LungeFormAnalyzer()

    private let squatCounter  = SquatCounter()
    private let pushUpCounter = PushUpCounter()
    private let lungeCounter  = LungeCounter()

    private var lastExercise: DetectedExercise = .unknown

    // Geometry-based squat validation (no ML lag).
    // The ML window is 2 s deep, so gating the counter on ML feedback causes
    // false counts — the window still shows the previous state at rep completion.
    // Instead, track depth + torso lean geometrically (instant).
    private var squatDescending     = false
    private var squatMinKneeAngle:   Double = 180.0
    private var squatMinDepthRatio:  Double = 1.0      // POV-robust depth, lower = deeper
    private var squatTorsoFault     = false
    private var squatRepView:        Viewpoint = .unknown   // locked at descent start
    private var squatStartTorsoH:    Double = 0.0      // torso height at top of rep
    private var squatMinTorsoH:      Double = .greatestFiniteMagnitude
    private var validSquatCount     = 0

    // Tunable thresholds — POV-specific because the two views see depth/lean
    // very differently.
    //
    // Depth (hipKneeDepthRatio: ~0.9 standing, 0 at parallel, negative below knee):
    //  - Side view: knee/hip are clearly separated, so demand hip BELOW knee.
    //  - Front view: hip detection is noisy and foreshortened, so "ass below knee"
    //    can't be measured reliably — accept parallel-ish depth instead.
    private let deepRatioSide:  Double = 0.0
    private let deepRatioFront: Double = 0.22
    // Torso fold (minTorsoHeight ÷ standingTorsoHeight) — torso folded forward:
    //  - Side view: a real lean tilts the torso, modest fold catches it.
    //  - Front view: a correct deep squat ALSO foreshortens the torso, so only
    //    a severe collapse counts (front lean is mainly caught by the ML model).
    private let foldLimitSide:  Double = 0.62
    private let foldLimitFront: Double = 0.40

    func feedObservation(_ obs: VNHumanBodyPoseObservation?) {
        squatMLClassifier.feedObservation(obs)
    }

    func analyze(joints: [DetectedJoint], confidenceThreshold: Float) -> ExerciseAnalysisResult {
        let features = PoseFeatureExtractor.extract(from: joints,
                                                     confidenceThreshold: confidenceThreshold)
        let exercise = detector.update(features: features)

        if exercise != lastExercise {
            squatCounter.reset()
            pushUpCounter.reset()
            lungeCounter.reset()
            resetSquatTracking()
            lastExercise = exercise
        }

        let feedback: FormFeedback
        let reps: Int

        switch exercise {
        case .squat:
            feedback = squatMLClassifier.analyze(features: features)

            let knee   = features.kneeAngleDegrees    ?? 180.0
            let spine  = features.spineAngleDeg        ?? 0.0
            let depth  = features.hipKneeDepthRatio
            let torsoH = features.torsoHeightNormalized

            // Detect start of descent (knee begins to bend).
            if !squatDescending && knee < 155.0 {
                squatDescending    = true
                squatMinKneeAngle  = knee
                squatMinDepthRatio = depth ?? 1.0
                squatTorsoFault    = false
                // Lock viewpoint while still upright — at the bottom the torso
                // foreshortens and shoulders occlude, so front/side detection is
                // unreliable there.
                squatRepView       = features.viewpoint
                squatStartTorsoH   = torsoH ?? 0.0       // upright reference
                squatMinTorsoH     = torsoH ?? .greatestFiniteMagnitude
            } else if squatDescending {
                squatMinKneeAngle = min(squatMinKneeAngle, knee)
                squatMinDepthRatio = min(squatMinDepthRatio, depth ?? squatMinDepthRatio)
                if let t = torsoH { squatMinTorsoH = min(squatMinTorsoH, t) }
                // If viewpoint was uncertain at the very first frame, adopt the
                // first confident reading taken while still fairly upright.
                if squatRepView == .unknown, knee > 135.0, features.viewpoint != .unknown {
                    squatRepView = features.viewpoint
                }

                // Angle-independent lean signals accumulated during the descent:
                //  1. Side-view spine angle (lean visible as a forward tilt).
                //  2. ML model classified torso_lean (learned from real videos).
                // The front-view torso-fold check is evaluated at rep completion
                // with a POV-specific limit (a correct deep squat folds too).
                if spine > 40.0 && knee < 160.0 { squatTorsoFault = true }
                if feedback == .torsoLean        { squatTorsoFault = true }
            }

            // Always update the phase tracker (detects down→up transition).
            let before = squatCounter.count
            squatCounter.update(kneeAngle: features.kneeAngleDegrees)
            if squatCounter.count > before {
                // Rep physically completed — count only if deep enough AND upright,
                // using thresholds appropriate to the viewpoint at the bottom.
                let isSide     = squatRepView == .side
                let deepLimit  = isSide ? deepRatioSide : deepRatioFront
                let foldLimit  = isSide ? foldLimitSide : foldLimitFront

                let deepEnough = squatMinDepthRatio < deepLimit
                let foldFault  = squatStartTorsoH > 0.01 &&
                                 (squatMinTorsoH / squatStartTorsoH) < foldLimit

                if deepEnough && !squatTorsoFault && !foldFault { validSquatCount += 1 }
                squatDescending = false
            }

            reps = validSquatCount

        case .pushUp:
            feedback = pushUpAnalyzer.analyze(features: features)
            pushUpCounter.update(elbowAngle: features.elbowAngleDegrees)
            reps = pushUpCounter.count

        case .lunge:
            feedback = lungeAnalyzer.analyze(features: features)
            lungeCounter.update(kneeAngle: features.kneeAngleDegrees)
            reps = lungeCounter.count

        case .unknown:
            feedback = features.bodyFullyVisible ? .goodForm : .bodyNotFullyVisible
            reps = 0
        }

        return ExerciseAnalysisResult(exercise: exercise,
                                      feedback: feedback,
                                      repCount: reps,
                                      viewpoint: features.viewpoint)
    }

    func resetCount() {
        squatCounter.reset()
        pushUpCounter.reset()
        lungeCounter.reset()
        resetSquatTracking()
    }

    private func resetSquatTracking() {
        squatDescending    = false
        squatMinKneeAngle  = 180.0
        squatMinDepthRatio = 1.0
        squatTorsoFault    = false
        squatRepView       = .unknown
        squatStartTorsoH   = 0.0
        squatMinTorsoH     = .greatestFiniteMagnitude
        validSquatCount    = 0
    }
}
