import CoreML
import Vision
import Foundation

/// Action-Classifier-backed form analyzer using a 60-frame sliding window of
/// raw body-pose observations. Each frame is fed via feedObservation(_:) and
/// the cached prediction is returned from analyze(features:).
///
/// Falls back to rule-based SquatFormAnalyzer until the window fills (first 2 s)
/// or if the model file isn't present in the bundle.
final class SquatMLClassifier: FormAnalyzer {

    private let classifier: SquatFormClassifier?
    private let fallback = SquatFormAnalyzer()

    private var poseWindow: [MLMultiArray] = []
    private let windowSize = 60
    private var cachedMLFeedback: FormFeedback?
    // Shape is discovered from the first real observation so zero-padding
    // always matches — mismatched shapes crash MLMultiArray(concatenating:).
    private var templateShape: [NSNumber]?
    // Throttle ML inference to every 5th frame (~6 fps) — running prediction
    // at 30 fps causes memory pressure and crashes after a few seconds.
    private var frameCounter = 0
    private let predictionStride = 5

    init() {
        classifier = try? SquatFormClassifier(configuration: MLModelConfiguration())
        if classifier == nil {
            print("[SquatMLClassifier] Model not found — using rule-based fallback.")
        }
    }

    /// Call once per camera frame (on the capture queue) with the latest
    /// VNHumanBodyPoseObservation, or nil when no person is detected.
    func feedObservation(_ obs: VNHumanBodyPoseObservation?) {
        let array: MLMultiArray

        if let obs, let keypoints = try? obs.keypointsMultiArray() {
            templateShape = keypoints.shape   // learn shape from first real frame
            array = keypoints
        } else {
            // Zero-pad only after we know the correct shape from a real frame.
            guard let shape = templateShape,
                  let zeros = try? MLMultiArray(shape: shape, dataType: .float)
            else { return }
            array = zeros
        }

        poseWindow.append(array)
        if poseWindow.count > windowSize { poseWindow.removeFirst() }

        frameCounter += 1
        guard poseWindow.count == windowSize,
              frameCounter >= predictionStride,
              let classifier else { return }
        frameCounter = 0

        // Build the [60, 3, 18] input MANUALLY instead of MLMultiArray(concatenating:).
        // concatenating raises an Objective-C NSException on any shape/type mismatch,
        // which try? cannot catch → hard crash. A manual buffer copy can never throw:
        // malformed frames are simply skipped (left as zeros).
        autoreleasepool {
            guard let input = try? MLMultiArray(
                shape: [NSNumber(value: windowSize), 3, 18], dataType: .float)
            else { return }

            let perFrame = 3 * 18  // 54 values per frame (3 channels × 18 joints)
            let dst = input.dataPointer.bindMemory(to: Float.self, capacity: input.count)
            for (f, frame) in poseWindow.enumerated() where frame.count == perFrame {
                let base = f * perFrame
                for i in 0..<perFrame { dst[base + i] = frame[i].floatValue }
            }

            if let out = try? classifier.prediction(poses: input) {
                cachedMLFeedback = FormFeedback(mlLabel: out.label)
            }
        }
    }

    func analyze(features: PoseFeatures) -> FormFeedback {
        guard features.bodyFullyVisible else { return .bodyNotFullyVisible }
        guard !features.lowConfidence   else { return .lowConfidence }

        // Geometry rule overrides ML when obvious torso lean is present.
        if let spineAngle = features.spineAngleDeg,
           let kneeAngle  = features.kneeAngleDegrees,
           kneeAngle < 160.0,
           spineAngle > 40.0 {
            return .torsoLean
        }

        return cachedMLFeedback ?? fallback.analyze(features: features)
    }
}

private extension FormFeedback {
    init?(mlLabel: String) {
        switch mlLabel {
        case "squat_correct":     self = .goodForm
        case "squat_too_shallow": self = .notDeepEnough
        case "squat_torso_lean":  self = .torsoLean
        default:                  return nil   // "other" / "none" → use fallback
        }
    }
}
