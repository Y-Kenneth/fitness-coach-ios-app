import AVFoundation
import SwiftUI
import Vision

// MARK: - Public view

struct PoseDetectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = PoseDetectionViewModel()

    private let confidenceThreshold: Float = 0.3

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.permissionDenied {
                permissionDeniedView
            } else {
                GeometryReader { geo in
                    ZStack {
                        CameraPreviewView(session: vm.session,
                                          mirror: vm.usingFrontCamera)
                            .ignoresSafeArea()

                        SkeletonOverlay(joints: vm.joints,
                                        size: geo.size,
                                        confidenceThreshold: confidenceThreshold,
                                        mirror: vm.usingFrontCamera)
                            .allowsHitTesting(false)
                    }
                }
                .ignoresSafeArea()
            }

            VStack {
                topBar
                Spacer()
                statusPill
                    .padding(.bottom, AppConstants.Spacing.xl)
            }
        }
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .statusBarHidden(true)
    }

    // MARK: Subviews

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("Close")

            Spacer()

            Button(action: { vm.flipCamera() }) {
                Image(systemName: "camera.rotate")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("Flip camera")
        }
        .padding(.horizontal, AppConstants.Spacing.md)
        .padding(.top, AppConstants.Spacing.sm)
    }

    private var statusPill: some View {
        Text(vm.isTracking ? "Tracking" : "No person detected")
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, AppConstants.Spacing.md)
            .padding(.vertical, AppConstants.Spacing.sm)
            .background((vm.isTracking ? Color.green : Color.red).opacity(0.85),
                        in: Capsule())
    }

    private var permissionDeniedView: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
            Text("Camera access is required for Form Check.")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Enable camera access in Settings to use this feature.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, AppConstants.Spacing.sm)
        }
        .padding(AppConstants.Spacing.lg)
    }
}

// MARK: - Camera preview (UIKit bridge)

/// Wraps AVCaptureVideoPreviewLayer for SwiftUI.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let mirror: Bool

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let connection = uiView.videoPreviewLayer.connection {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            // Front camera looks more natural mirrored; back camera should not be.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirror
            }
        }
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - Skeleton overlay

private struct SkeletonOverlay: View {
    let joints: [DetectedJoint]
    let size: CGSize
    let confidenceThreshold: Float
    let mirror: Bool

    /// Logical bones: pairs of joints that should be connected with a line.
    private static let bones: [(VNHumanBodyPoseObservation.JointName,
                                VNHumanBodyPoseObservation.JointName)] = [
        // Head / torso
        (.nose, .neck),
        (.neck, .leftShoulder),
        (.neck, .rightShoulder),
        (.neck, .root),
        (.root, .leftHip),
        (.root, .rightHip),
        // Left arm
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        // Right arm
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        // Left leg
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        // Right leg
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        // Shoulder-to-hip side lines (helps visualize torso width)
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip)
    ]

    var body: some View {
        Canvas { ctx, _ in
            let map = Dictionary(uniqueKeysWithValues: joints.map { ($0.name, $0) })

            // Draw bones first so joints sit on top.
            for (a, b) in Self.bones {
                guard
                    let ja = map[a], ja.confidence >= confidenceThreshold,
                    let jb = map[b], jb.confidence >= confidenceThreshold
                else { continue }
                var path = Path()
                path.move(to: convert(ja.point))
                path.addLine(to: convert(jb.point))
                ctx.stroke(path,
                           with: .color(.green.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            for joint in joints where joint.confidence >= confidenceThreshold {
                let p = convert(joint.point)
                let rect = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: rect), with: .color(.yellow))
            }
        }
    }

    /// Convert Vision's normalized point (origin bottom-left, 0…1) to SwiftUI
    /// view coordinates (origin top-left, in points). Vertical axis must be
    /// flipped. For the front camera the preview is mirrored, so the skeleton
    /// has to be mirrored horizontally as well to stay aligned with the user.
    private func convert(_ p: CGPoint) -> CGPoint {
        let x = mirror ? (1.0 - p.x) : p.x
        let y = 1.0 - p.y
        return CGPoint(x: x * size.width, y: y * size.height)
    }
}
