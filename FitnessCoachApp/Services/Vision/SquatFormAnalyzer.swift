import CoreGraphics
import Foundation
import Vision

// MARK: - HealthyAgent ↔ MLAgent boundary
//
// The lecture's data flow: Camera frame → AVFoundation capture → Vision body
// pose request → Joint points → Feature extraction → Rule-based form analyzer
// → SwiftUI feedback. The HealthyAgent owns the AVFoundation capture pipeline
// and emits frames; the MLAgent consumes them through this small protocol.
// Keeping the seam here means the analyzer is testable with mock joint streams
// and the camera implementation can be swapped (e.g. recorded video for QA).

/// Receives pose observations from a frame source.
/// Implementations should be thread-safe; the camera service may call this on a
/// capture queue, not the main thread.
protocol PoseConsumer: AnyObject {
    func didDetectJoints(_ joints: [DetectedJoint])
}

/// HealthyAgent surface: a camera that produces pose observations on a stream.
protocol CameraFrameService: AnyObject {
    func start()
    func stop()
    func setConsumer(_ consumer: PoseConsumer?)
}

// MARK: - Feature extraction (MLAgent: shape data the rules need)
//
// Vision returns 19 raw joints. The form rules don't want raw joints; they want
// derived features — angles, side-symmetry, whether the frame even contains a
// full body. Centralizing these here keeps the rule layer declarative.

/// Which way the camera is facing the user. Squat depth is measured very
/// differently depending on this: from the side the knee angle is accurate,
/// from the front it's foreshortened (a shallow squat can look deep).
enum Viewpoint: String {
    case front   = "FRONT VIEW"
    case side    = "SIDE VIEW"
    case unknown = "DETECTING…"
}

struct PoseFeatures {

    let bodyFullyVisible: Bool
    let lowConfidence: Bool

    // Squat
    let kneeAngleDegrees: Double?          // averaged L+R, 180° standing → 70° deep squat
    let hipAngleDegrees: Double?           // 180° upright → smaller when bent
    let kneeAnkleDriftNormalized: Double?  // horizontal knee-ankle offset (alignment)
    /// Vertical hip-above-knee gap ÷ torso height. POV-ROBUST depth measure:
    /// ~0.9 standing, ~0 at parallel (hip level with knee), negative below.
    /// Unlike knee angle this isn't fooled by camera perspective.
    let hipKneeDepthRatio: Double?
    /// Vertical distance between shoulder-center and hip-center (normalized).
    /// Shrinks when the torso folds forward — used to catch torso lean from the
    /// FRONT, where the lean is along the camera axis and spine angle can't see it.
    let torsoHeightNormalized: Double?
    /// Detected camera viewpoint relative to the user.
    let viewpoint: Viewpoint

    // Exercise detection
    /// Spine angle from vertical: 0° = fully upright, 90° = horizontal (push-up prone).
    let spineAngleDeg: Double?
    /// |leftKneeAngle − rightKneeAngle|: large in lunges, near zero in squats.
    let kneeAngleDiffDeg: Double?

    // Push-up
    /// Average elbow flexion (shoulder-elbow-wrist). 180° = straight arm.
    let elbowAngleDegrees: Double?
    /// Signed distance of hip from the shoulder-to-ankle line.
    /// Positive = pike (hips raised), negative = sag (hips dropped).
    let hipSagOffset: Double?
    /// Elbow spread / shoulder width. Values > 1.5 indicate elbows too wide.
    let elbowSpreadRatio: Double?

    // Jumping jack / arm + stance tracking
    /// Both wrists raised above shoulder level.
    let wristsAboveShoulders: Bool
    /// Both wrists raised above the head (full overhead extension).
    let wristsAboveHead: Bool
    /// Horizontal ankle spread ÷ shoulder width (stance width). Front view only.
    let ankleSpreadRatio: Double?
    /// Horizontal knee spread ÷ shoulder width. Much smaller than the ankle
    /// spread means the knees are caving inward (valgus). Front view only.
    let kneeSpreadRatio: Double?

    static let empty = PoseFeatures(
        bodyFullyVisible: false, lowConfidence: true,
        kneeAngleDegrees: nil, hipAngleDegrees: nil, kneeAnkleDriftNormalized: nil,
        hipKneeDepthRatio: nil, torsoHeightNormalized: nil, viewpoint: .unknown,
        spineAngleDeg: nil, kneeAngleDiffDeg: nil,
        elbowAngleDegrees: nil, hipSagOffset: nil, elbowSpreadRatio: nil,
        wristsAboveShoulders: false, wristsAboveHead: false,
        ankleSpreadRatio: nil, kneeSpreadRatio: nil)
}

enum PoseFeatureExtractor {

    /// Map joint -> point only when it clears the per-joint confidence floor.
    static func extract(from joints: [DetectedJoint],
                        confidenceThreshold: Float) -> PoseFeatures {
        let byName = Dictionary(uniqueKeysWithValues: joints.map { ($0.name, $0) })

        // Coverage check using OR across each bilateral pair.
        // A side-view photo only shows one side of the body, so requiring
        // BOTH leftKnee AND rightKnee would always fail. We only need at
        // least one confident joint per anatomical region.
        let confident: (VNHumanBodyPoseObservation.JointName) -> Bool = {
            (byName[$0]?.confidence ?? 0) >= confidenceThreshold
        }
        let bodyFullyVisible =
            (confident(.leftHip)      || confident(.rightHip))      &&
            (confident(.leftKnee)     || confident(.rightKnee))     &&
            (confident(.leftAnkle)    || confident(.rightAnkle))    &&
            (confident(.leftShoulder) || confident(.rightShoulder))

        // Lower floor (4) so one-sided detections are still trusted.
        let usable = joints.filter { $0.confidence >= confidenceThreshold }
        let lowConfidence = usable.count < 4

        // Knee angle = angle at the knee joint (hip-knee-ankle).
        let leftKneeAngle  = angle(at: byName[.leftKnee],  a: byName[.leftHip],  c: byName[.leftAnkle])
        let rightKneeAngle = angle(at: byName[.rightKnee], a: byName[.rightHip], c: byName[.rightAnkle])
        let kneeAngle = averageNonNil(leftKneeAngle, rightKneeAngle)

        // Hip angle = angle at the hip (shoulder-hip-knee).
        let leftHipAngle  = angle(at: byName[.leftHip],  a: byName[.leftShoulder],  c: byName[.leftKnee])
        let rightHipAngle = angle(at: byName[.rightHip], a: byName[.rightShoulder], c: byName[.rightKnee])
        let hipAngle = averageNonNil(leftHipAngle, rightHipAngle)

        // Knee-over-ankle horizontal drift (alignment proxy).
        let leftDrift  = horizontalDrift(knee: byName[.leftKnee],  ankle: byName[.leftAnkle])
        let rightDrift = horizontalDrift(knee: byName[.rightKnee], ankle: byName[.rightAnkle])
        let drift = averageNonNil(leftDrift, rightDrift)

        // Spine angle from vertical (push-up vs upright detection).
        let hipCenter   = midpoint(byName[.leftHip],      byName[.rightHip])
        let shoulderCtr = midpoint(byName[.leftShoulder], byName[.rightShoulder])
        let spineAngle  = angleFromVertical(from: hipCenter, to: shoulderCtr)

        // Knee angle asymmetry (lunge vs squat detection).
        let kneeAngleDiff: Double?
        switch (leftKneeAngle, rightKneeAngle) {
        case let (l?, r?): kneeAngleDiff = abs(l - r)
        default: kneeAngleDiff = nil
        }

        // Elbow flexion (push-up rep counting + depth feedback).
        let leftElbow  = angle(at: byName[.leftElbow],  a: byName[.leftShoulder],  c: byName[.leftWrist])
        let rightElbow = angle(at: byName[.rightElbow], a: byName[.rightShoulder], c: byName[.rightWrist])
        let elbowAngle = averageNonNil(leftElbow, rightElbow)

        // Hip sag / pike (push-up body-line feedback).
        let ankleCenter = midpoint(byName[.leftAnkle], byName[.rightAnkle])
        let hipCtr      = midpoint(byName[.leftHip],   byName[.rightHip])
        let hipSag      = signedHipOffset(shoulder: shoulderCtr, hip: hipCtr, ankle: ankleCenter)

        // Elbow spread ratio (push-up elbow-flare feedback).
        let elbowSpreadRatio: Double?
        if let le = byName[.leftElbow]?.point,  let re = byName[.rightElbow]?.point,
           let ls = byName[.leftShoulder]?.point, let rs = byName[.rightShoulder]?.point {
            let ew = abs(Double(le.x - re.x))
            let sw = abs(Double(ls.x - rs.x))
            elbowSpreadRatio = sw > 0.01 ? ew / sw : nil
        } else {
            elbowSpreadRatio = nil
        }

        // Confident-point lookup (only trust joints above the threshold) — used
        // for viewpoint detection so a low-confidence "ghost" far-side joint
        // doesn't make a side view look like a front view.
        let cpt: (VNHumanBodyPoseObservation.JointName) -> CGPoint? = {
            guard let j = byName[$0], j.confidence >= confidenceThreshold else { return nil }
            return j.point
        }

        // Viewpoint detection: from the front, the shoulders/hips span a wide
        // horizontal distance relative to torso height. From the side they
        // collapse onto each other (or one side isn't even detected).
        let torsoHeight: Double? = {
            guard let s = shoulderCtr, let h = hipCenter else { return nil }
            return abs(Double(s.y - h.y))
        }()
        let shoulderSpan: Double? = {
            guard let l = cpt(.leftShoulder), let r = cpt(.rightShoulder) else { return nil }
            return abs(Double(l.x - r.x))
        }()
        let hipSpan: Double? = {
            guard let l = cpt(.leftHip), let r = cpt(.rightHip) else { return nil }
            return abs(Double(l.x - r.x))
        }()

        let viewpoint: Viewpoint
        let spans = [shoulderSpan, hipSpan].compactMap { $0 }
        if spans.isEmpty {
            // Only one side of the body is confidently visible → side-on.
            viewpoint = bodyFullyVisible ? .side : .unknown
        } else if let th = torsoHeight, th > 0.01, let widest = spans.max() {
            let ratio = widest / th
            if ratio >= 0.42      { viewpoint = .front }
            else if ratio <= 0.24 { viewpoint = .side }
            else                  { viewpoint = .unknown }
        } else {
            viewpoint = .unknown
        }

        // POV-robust depth: vertical gap between hip and knee, normalized by
        // torso height. Works the same from any angle because it's a vertical
        // measure — a shallow squat can't fake this the way it fakes knee angle.
        let kneeY: Double? = {
            let ys = [cpt(.leftKnee)?.y, cpt(.rightKnee)?.y].compactMap { $0 }
            guard !ys.isEmpty else { return nil }
            return Double(ys.reduce(0, +)) / Double(ys.count)
        }()
        let hipKneeDepthRatio: Double? = {
            guard let h = hipCenter, let ky = kneeY,
                  let th = torsoHeight, th > 0.01 else { return nil }
            return (Double(h.y) - ky) / th   // ~0.9 standing, ~0 at parallel
        }()

        // Arm elevation (jumping jacks). Vision Y is up, so "above" = larger y.
        let shoulderY = shoulderCtr.map { Double($0.y) }
        let wristYs   = [cpt(.leftWrist)?.y, cpt(.rightWrist)?.y].compactMap { $0 }.map { Double($0) }
        let bothWrists = wristYs.count == 2
        let wristsAboveShoulders: Bool = {
            guard bothWrists, let sy = shoulderY else { return false }
            return wristYs.allSatisfy { $0 > sy }
        }()
        let headY = cpt(.nose).map { Double($0.y) } ?? shoulderY.map { $0 + 0.12 }
        let wristsAboveHead: Bool = {
            guard bothWrists, let hy = headY else { return false }
            return wristYs.allSatisfy { $0 > hy }
        }()

        // Stance / knee width (front-view squat faults). Needs both sides, so
        // these are nil in side view and never produce false warnings there.
        let widthNorm = [shoulderSpan, hipSpan].compactMap { $0 }.max()
        let ankleSpreadRatio: Double? = {
            guard let l = cpt(.leftAnkle), let r = cpt(.rightAnkle),
                  let w = widthNorm, w > 0.01 else { return nil }
            return abs(Double(l.x - r.x)) / w
        }()
        let kneeSpreadRatio: Double? = {
            guard let l = cpt(.leftKnee), let r = cpt(.rightKnee),
                  let w = widthNorm, w > 0.01 else { return nil }
            return abs(Double(l.x - r.x)) / w
        }()

        return PoseFeatures(
            bodyFullyVisible: bodyFullyVisible,
            lowConfidence: lowConfidence,
            kneeAngleDegrees: kneeAngle,
            hipAngleDegrees: hipAngle,
            kneeAnkleDriftNormalized: drift,
            hipKneeDepthRatio: hipKneeDepthRatio,
            torsoHeightNormalized: torsoHeight,
            viewpoint: viewpoint,
            spineAngleDeg: spineAngle,
            kneeAngleDiffDeg: kneeAngleDiff,
            elbowAngleDegrees: elbowAngle,
            hipSagOffset: hipSag,
            elbowSpreadRatio: elbowSpreadRatio,
            wristsAboveShoulders: wristsAboveShoulders,
            wristsAboveHead: wristsAboveHead,
            ankleSpreadRatio: ankleSpreadRatio,
            kneeSpreadRatio: kneeSpreadRatio)
    }

    // Interior angle at vertex `at`, formed by edges to points `a` and `c`.
    private static func angle(at vertex: DetectedJoint?,
                              a: DetectedJoint?,
                              c: DetectedJoint?) -> Double? {
        guard let v = vertex?.point, let p1 = a?.point, let p2 = c?.point else {
            return nil
        }
        let v1 = CGPoint(x: p1.x - v.x, y: p1.y - v.y)
        let v2 = CGPoint(x: p2.x - v.x, y: p2.y - v.y)
        let dot = Double(v1.x * v2.x + v1.y * v2.y)
        let mag = sqrt(Double(v1.x * v1.x + v1.y * v1.y)) *
                  sqrt(Double(v2.x * v2.x + v2.y * v2.y))
        guard mag > 1e-6 else { return nil }
        let cosA = max(-1.0, min(1.0, dot / mag))
        return acos(cosA) * 180.0 / .pi
    }

    private static func horizontalDrift(knee: DetectedJoint?,
                                        ankle: DetectedJoint?) -> Double? {
        guard let k = knee?.point, let a = ankle?.point else { return nil }
        return abs(Double(k.x - a.x))
    }

    private static func averageNonNil(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case let (x?, y?): return (x + y) / 2.0
        case let (x?, nil): return x
        case let (nil, y?): return y
        default:           return nil
        }
    }

    private static func midpoint(_ a: DetectedJoint?, _ b: DetectedJoint?) -> CGPoint? {
        switch (a?.point, b?.point) {
        case let (p?, q?): return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        case let (p?, nil): return p
        case let (nil, q?): return q
        default: return nil
        }
    }

    // Angle of the (from → to) vector from the upward vertical (0, 1).
    // Vision Y is up, so an upright spine (hip→shoulder pointing up) returns ~0°;
    // a horizontal spine (push-up prone) returns ~90°.
    private static func angleFromVertical(from a: CGPoint?, to b: CGPoint?) -> Double? {
        guard let a, let b else { return nil }
        let dy = Double(b.y - a.y), dx = Double(b.x - a.x)
        let mag = sqrt(dx * dx + dy * dy)
        guard mag > 1e-6 else { return nil }
        return acos(max(-1.0, min(1.0, dy / mag))) * 180.0 / .pi
    }

    // Signed distance of `hip` from the line through `shoulder` and `ankle`.
    // Positive = hip above the line (pike), negative = below (sag).
    private static func signedHipOffset(shoulder: CGPoint?, hip: CGPoint?, ankle: CGPoint?) -> Double? {
        guard let s = shoulder, let h = hip, let a = ankle else { return nil }
        let dx = Double(a.x - s.x), dy = Double(a.y - s.y)
        let len = sqrt(dx * dx + dy * dy)
        guard len > 1e-6 else { return nil }
        return (dx * Double(h.y - s.y) - dy * Double(h.x - s.x)) / len
    }
}

// MARK: - Form feedback (UIAgent surface)
//
// Exactly the five states the lecture's MVP scope calls out. The UI maps each
// to a color + message; the analyzer just classifies.

enum FormFeedback: Equatable {
    // Universal
    case goodForm
    case bodyNotFullyVisible
    case lowConfidence

    // Squat
    case notDeepEnough
    case kneeAlignmentIssue
    case torsoLean
    case squatStanceTooNarrow
    case squatKneesInward

    // Push-up
    case hipsSagging
    case hipsRaised
    case elbowsTooWide
    case pushUpNotLowEnough

    // Lunge
    case lungeKneeForward
    case lungeNotDeepEnough
    case lungeForwardLean

    // Jumping jack
    case jumpingJackArmsLow
    case jumpingJackLegsNarrow

    var headline: String {
        switch self {
        case .goodForm:             return "Good form"
        case .bodyNotFullyVisible:  return "Step back — body not fully in frame"
        case .lowConfidence:        return "Can't read your pose clearly"
        case .notDeepEnough:        return "Go deeper"
        case .kneeAlignmentIssue:   return "Watch your knee alignment"
        case .torsoLean:            return "Lift your chest"
        case .squatStanceTooNarrow: return "Widen your stance"
        case .squatKneesInward:     return "Push your knees out"
        case .hipsSagging:          return "Hips sagging"
        case .hipsRaised:           return "Hips too high"
        case .elbowsTooWide:        return "Elbows too wide"
        case .pushUpNotLowEnough:   return "Go lower"
        case .lungeKneeForward:     return "Knee past toes"
        case .lungeNotDeepEnough:   return "Go deeper"
        case .lungeForwardLean:     return "Stay upright"
        case .jumpingJackArmsLow:   return "Raise your arms higher"
        case .jumpingJackLegsNarrow: return "Jump your feet wider"
        }
    }

    var detail: String {
        switch self {
        case .goodForm:
            return "Looking great — keep it up."
        case .bodyNotFullyVisible:
            return "Move so your hips, knees, and ankles are all visible."
        case .lowConfidence:
            return "Try better lighting or a less busy background."
        case .notDeepEnough:
            return "Drop your hips closer to knee level for a full squat."
        case .kneeAlignmentIssue:
            return "Track your knees in line with your toes — don't let them drift."
        case .torsoLean:
            return "You're leaning too far forward. Lift your chest and keep your torso more upright."
        case .squatStanceTooNarrow:
            return "Your feet are too close together. Step them out to about shoulder width."
        case .squatKneesInward:
            return "Your knees are caving in. Push them out so they track over your toes."
        case .hipsSagging:
            return "Engage your core to keep your body in a straight line."
        case .hipsRaised:
            return "Lower your hips — your body should form a straight plank."
        case .elbowsTooWide:
            return "Tuck your elbows to about 45° from your torso."
        case .pushUpNotLowEnough:
            return "Lower your chest closer to the floor before pressing back up."
        case .lungeKneeForward:
            return "Keep your front knee directly above your ankle, not past it."
        case .lungeNotDeepEnough:
            return "Lower your back knee closer to the floor for full range of motion."
        case .lungeForwardLean:
            return "Keep your torso upright — engage your core and pull your shoulders back."
        case .jumpingJackArmsLow:
            return "Raise your arms all the way overhead until your hands nearly touch."
        case .jumpingJackLegsNarrow:
            return "Jump your feet out wider than your shoulders on each rep."
        }
    }

    var voicePrompt: String {
        switch self {
        case .goodForm:             return "Great form, keep it up."
        case .bodyNotFullyVisible:  return "Step back. Full body not in frame."
        case .lowConfidence:        return ""
        case .notDeepEnough:        return "Squat deeper."
        case .kneeAlignmentIssue:   return "Watch your knee alignment."
        case .torsoLean:            return "Lift your chest up."
        case .squatStanceTooNarrow: return "Widen your stance."
        case .squatKneesInward:     return "Push your knees out."
        case .hipsSagging:          return "Engage your core."
        case .hipsRaised:           return "Lower your hips."
        case .elbowsTooWide:        return "Tuck your elbows in."
        case .pushUpNotLowEnough:   return "Go lower."
        case .lungeKneeForward:     return "Keep your knee back."
        case .lungeNotDeepEnough:   return "Lunge deeper."
        case .lungeForwardLean:     return "Stay upright."
        case .jumpingJackArmsLow:   return "Raise your arms higher."
        case .jumpingJackLegsNarrow: return "Jump your feet wider."
        }
    }
}

// MARK: - Rep counter (state machine: up → down → up = 1 rep)

final class SquatCounter {
    private enum Phase { case up, down }
    private var phase: Phase = .up
    private(set) var count = 0

    // Hysteresis band prevents noise near the threshold from double-counting.
    private let downAngle: Double = 100.0   // angle must drop BELOW this to count as "down"
    private let upAngle:   Double = 155.0   // angle must rise ABOVE this to complete the rep

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

// MARK: - Rule-based form analyzer (MLAgent's rule layer)
//
// "Builds rule-based form feedback" per the agents-used-today slide. The
// thresholds are intentionally simple and hand-tunable — this is the MVP that
// the lecture says will eventually graduate into a Core ML classifier.
// The lecture's migration path:
//   Same input features (joint angles, visibility) →
//   Today: hand-written if/else → Tomorrow: Core ML classifier returning
//   FormFeedback as the output class.

protocol FormAnalyzer {
    func analyze(features: PoseFeatures) -> FormFeedback
}

/// Squat-specific rule analyzer. MVP scope explicitly says "Squat exercise first".
struct SquatFormAnalyzer: FormAnalyzer {

    // Tunable thresholds. Default values calibrated for front-facing camera
    // at typical home-gym framing; expose for QAAgent to sweep on device.
    struct Thresholds {
        /// Below this knee angle the squat counts as deep enough.
        /// 180° = standing, 100° ≈ thighs parallel to floor, 70° = ass-to-grass.
        var deepEnoughKneeAngle: Double = 110.0
        /// Above this, user is essentially standing — don't critique depth.
        var standingKneeAngle: Double   = 160.0
        /// Drift (normalized image units) above which knees are tracking off-line.
        var maxKneeAnkleDrift: Double   = 0.08
        /// Spine angle from vertical (degrees) above which torso is leaning too far forward.
        /// 0° = fully upright, ~90° = horizontal (push-up). Normal squat lean ≤ 25°.
        var maxTorsoLeanAngle: Double   = 40.0
    }

    var thresholds = Thresholds()

    func analyze(features: PoseFeatures) -> FormFeedback {
        // Coverage rules fire first — without joints, we have nothing to say.
        if !features.bodyFullyVisible { return .bodyNotFullyVisible }
        if features.lowConfidence     { return .lowConfidence }

        guard let kneeAngle = features.kneeAngleDegrees else {
            return .bodyNotFullyVisible
        }

        // When the user is upright we don't critique depth or alignment.
        if kneeAngle >= thresholds.standingKneeAngle {
            return .goodForm
        }

        // Mid-rep: check alignment first (a structural fault matters more than
        // depth — going deeper on a misaligned knee compounds the injury risk).
        if let drift = features.kneeAnkleDriftNormalized,
           drift > thresholds.maxKneeAnkleDrift {
            return .kneeAlignmentIssue
        }

        // Torso lean — excessive forward lean during the squat.
        if let spineAngle = features.spineAngleDeg,
           spineAngle > thresholds.maxTorsoLeanAngle {
            return .torsoLean
        }

        // Then depth.
        if kneeAngle > thresholds.deepEnoughKneeAngle {
            return .notDeepEnough
        }

        return .goodForm
    }
}
