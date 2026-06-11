import PhotosUI
import SwiftUI
import Vision

// MARK: - Image-based pose test
//
// Runs the exact same Vision pipeline as the live camera session but on a
// still photo. Useful for verifying joint detection, skeleton drawing, and the
// form analyzer without a physical iPhone. Workflow:
//   1. Pick any photo of a person squatting (Google → drag into Simulator).
//   2. Vision detects hip, knee, ankle, shoulder positions.
//   3. Skeleton lines and FormFeedbackCard render on the image.

struct ImagePoseTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var displayImage: UIImage?
    @State private var joints: [DetectedJoint] = []
    @State private var feedback: FormFeedback = .bodyNotFullyVisible
    @State private var isAnalyzing = false

    // Static photos lack the temporal context live video has, so Vision returns
    // lower per-joint confidence. Use a lower floor than the live camera (0.3)
    // so photo analysis is still meaningful.
    private let confidenceThreshold: Float = 0.1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if let img = displayImage {
                    GeometryReader { geo in
                        ZStack {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            if isAnalyzing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .scaleEffect(2)
                            } else {
                                ImageSkeletonOverlay(
                                    joints: joints,
                                    image: img,
                                    containerSize: geo.size,
                                    confidenceThreshold: confidenceThreshold
                                )
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    FormFeedbackCard(feedback: feedback)
                        .padding(.horizontal, AppConstants.Spacing.md)
                        .padding(.vertical, AppConstants.Spacing.sm)
                } else {
                    emptyState
                }
            }
        }
        .onChange(of: selectedItem) { item in
            guard let item else { return }
            isAnalyzing = true
            Task {
                defer { isAnalyzing = false }
                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let img = UIImage(data: data)
                else { return }
                displayImage = img
                // Pass raw Data — Vision reads EXIF orientation from it directly.
                let (detected, result) = await runVision(with: data)
                joints = detected
                feedback = result
            }
        }
    }

    // MARK: Subviews

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("Close")

            Spacer()

            Label("Photo Form Check", systemImage: "photo")
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            Spacer()

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("Choose photo")
        }
        .padding(.horizontal, AppConstants.Spacing.md)
        .padding(.top, AppConstants.Spacing.sm)
        .padding(.bottom, AppConstants.Spacing.sm)
    }

    private var emptyState: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.35))
            Text("Pick a photo to test form detection")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Text("Find a squat photo online, drag it into Simulator → Photos, then pick it here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppConstants.Spacing.xl)
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.badge.plus")
                    .font(.headline.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppConstants.Color.accent)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, AppConstants.Spacing.xl)
            .padding(.top, AppConstants.Spacing.sm)
            Spacer()
        }
    }

    // MARK: Vision (runs on background thread)

    // Pass raw image Data — VNImageRequestHandler(data:) reads EXIF orientation
    // from the file header automatically. This avoids every manual CGImage /
    // UIImage orientation conversion that was failing before.
    private func runVision(with imageData: Data) async -> ([DetectedJoint], FormFeedback) {
        let threshold = confidenceThreshold
        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(data: imageData, options: [:])
            do {
                try handler.perform([request])
                guard let obs = request.results?.first else {
                    print("[Vision] no person detected in image")
                    return ([DetectedJoint](), FormFeedback.bodyNotFullyVisible)
                }
                let recognized = try obs.recognizedPoints(.all)
                // Log all joints so we can see what Vision actually detected.
                let sorted = recognized.sorted { $0.value.confidence > $1.value.confidence }
                print("[Vision] top joints: \(sorted.prefix(6).map { "\($0.key.rawValue): \(String(format: "%.2f", $0.value.confidence))" })")
                let detected: [DetectedJoint] = recognized.compactMap { name, pt in
                    guard pt.confidence > 0 else { return nil }
                    return DetectedJoint(name: name,
                                        point: CGPoint(x: pt.location.x, y: pt.location.y),
                                        confidence: pt.confidence)
                }
                let features = PoseFeatureExtractor.extract(from: detected,
                                                            confidenceThreshold: threshold)
                let result = SquatFormAnalyzer().analyze(features: features)
                print("[Vision] bodyVisible=\(features.bodyFullyVisible) lowConf=\(features.lowConfidence) kneeAngle=\(features.kneeAngleDegrees.map { String(format: "%.1f°", $0) } ?? "nil") → \(result)")
                return (detected, result)
            } catch {
                print("[Vision] handler error: \(error)")
                return ([DetectedJoint](), FormFeedback.bodyNotFullyVisible)
            }
        }.value
    }
}

// MARK: - Image skeleton overlay
//
// Same bones and joint-dot logic as SkeletonOverlay in PoseDetectionView, but
// coordinates are mapped to the image's actual rendered rect inside the
// container (accounting for aspect-ratio letterboxing).

private struct ImageSkeletonOverlay: View {
    let joints: [DetectedJoint]
    let image: UIImage
    let containerSize: CGSize
    let confidenceThreshold: Float

    private static let bones: [(VNHumanBodyPoseObservation.JointName,
                                VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .neck),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip)
    ]

    var body: some View {
        Canvas { ctx, _ in
            let (renderedSize, offset) = imageRenderFrame()
            let map = Dictionary(uniqueKeysWithValues: joints.map { ($0.name, $0) })

            for (a, b) in Self.bones {
                guard
                    let ja = map[a], ja.confidence >= confidenceThreshold,
                    let jb = map[b], jb.confidence >= confidenceThreshold
                else { continue }
                var path = Path()
                path.move(to: convert(ja.point, size: renderedSize, offset: offset))
                path.addLine(to: convert(jb.point, size: renderedSize, offset: offset))
                ctx.stroke(path,
                           with: .color(.green.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            for joint in joints where joint.confidence >= confidenceThreshold {
                let p = convert(joint.point, size: renderedSize, offset: offset)
                let rect = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: rect), with: .color(.yellow))
            }
        }
    }

    // When .scaledToFit() renders an image inside a container it preserves
    // aspect ratio and may letterbox (unused space top/bottom) or pillarbox
    // (unused space left/right). Calculate the actual rendered rect so the
    // skeleton lands exactly on the pixels, not on black padding.
    private func imageRenderFrame() -> (CGSize, CGPoint) {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return (.zero, .zero) }
        let cw = containerSize.width, ch = containerSize.height
        let imageAspect = iw / ih
        let containerAspect = cw / ch

        if imageAspect > containerAspect {
            let h = cw / imageAspect
            return (CGSize(width: cw, height: h),
                    CGPoint(x: 0, y: (ch - h) / 2))
        } else {
            let w = ch * imageAspect
            return (CGSize(width: w, height: ch),
                    CGPoint(x: (cw - w) / 2, y: 0))
        }
    }

    // Vision: origin bottom-left, y-up, 0…1.
    // SwiftUI Canvas: origin top-left, y-down.
    private func convert(_ p: CGPoint, size: CGSize, offset: CGPoint) -> CGPoint {
        CGPoint(x: offset.x + p.x * size.width,
                y: offset.y + (1.0 - p.y) * size.height)
    }
}

