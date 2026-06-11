import AVFoundation
import SwiftUI
import Vision

// MARK: - Public view

struct PoseDetectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @StateObject private var vm = PoseDetectionViewModel()
    @State private var showingPhotoTest = false
    @State private var showingHistory = false

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
                                        feedback: vm.formFeedback)
                            .allowsHitTesting(false)

                        // Top fade for top bar legibility
                        VStack {
                            LinearGradient(
                                colors: [.black.opacity(0.72), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: geo.size.height * 0.28)
                            Spacer()
                            // Bottom fade for card legibility
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.88)],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: geo.size.height * 0.42)
                        }
                        .ignoresSafeArea()
                    }
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                detectionInfoBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                FormFeedbackCard(feedback: vm.formFeedback)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                Spacer()
                LiveFormBadge(feedback: vm.formFeedback)
                    .padding(.bottom, 10)
                bottomPanel
            }
        }
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .onChange(of: vm.sessionSets.count) { _ in
            guard let latest = vm.sessionSets.last else { return }
            workoutVM.recordExternalSession(
                workoutName: "Form Check — \(latest.exercise.rawValue)",
                durationMinutes: max(1, latest.reps / 12),
                caloriesBurned: Int(latest.calories.rounded())
            )
            Task {
                try? await workoutVM.healthProvider.writeWorkoutCalories(
                    latest.calories, date: latest.completedAt)
            }
        }
        .statusBarHidden(true)
        .fullScreenCover(isPresented: $showingPhotoTest) {
            ImagePoseTestView()
        }
        .sheet(isPresented: $showingHistory) {
            FormCheckHistorySheet(sets: vm.sessionSets, totalCalories: vm.totalSessionCalories)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            }
            .accessibilityLabel("Close")

            Spacer()

            HStack(spacing: 10) {
                Button(action: { showingPhotoTest = true }) {
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.accent)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                .accessibilityLabel("Test with photo")

                Button(action: { showingHistory = true }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppConstants.Color.accent)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.12), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                        if !vm.sessionSets.isEmpty {
                            Circle()
                                .fill(AppConstants.Color.warn)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .accessibilityLabel("Session history")

                Button(action: { vm.voiceMuted.toggle() }) {
                    Image(systemName: vm.voiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(vm.voiceMuted ? AppConstants.Color.warn : AppConstants.Color.accent)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                .accessibilityLabel(vm.voiceMuted ? "Unmute voice coaching" : "Mute voice coaching")

                Button(action: { vm.flipCamera() }) {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.accent)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                .accessibilityLabel("Flip camera")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: Detection info bar

    private var detectionInfoBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.detectedExercise == .unknown
                      ? AppConstants.Color.warn
                      : AppConstants.Color.accent)
                .frame(width: 7, height: 7)
                .shadow(color: AppConstants.Color.accent, radius: 4)
                .opacity(vm.detectedExercise == .unknown ? 0.6 : 1)
            Text(vm.detectedExercise.displayName)
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white)
                .animation(.easeOut(duration: 0.25), value: vm.detectedExercise)

            if vm.detectedExercise == .squat && vm.viewpoint != .unknown {
                Text(vm.viewpoint.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(AppConstants.Color.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(AppConstants.Color.accent.opacity(0.15))
                            .overlay(Capsule().stroke(AppConstants.Color.accent.opacity(0.4), lineWidth: 0.5))
                    )
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.25), value: vm.viewpoint)
            }

            Spacer()
            if vm.isTracking {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppConstants.Color.accent)
                        .frame(width: 5, height: 5)
                    Text("TRACKING")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(AppConstants.Color.accent.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppConstants.Color.accent.opacity(0.3), lineWidth: 1))
        )
    }

    // MARK: Bottom panel

    private var bottomPanel: some View {
        RepCounterCard(count: vm.repCount,
                       label: vm.detectedExercise.repLabel,
                       onReset: { vm.resetCount() })
            .padding(.horizontal, 16)
            .padding(.bottom, 56)
    }

    // MARK: Permission denied

    private var permissionDeniedView: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppConstants.Color.accent)
            Text("Camera Access Required")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Enable camera access in Settings to use Form Check.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(FCPrimaryButtonStyle())
                .padding(.top, AppConstants.Spacing.sm)
        }
        .padding(AppConstants.Spacing.lg)
    }
}

// MARK: - Rep counter card

private struct RepCounterCard: View {
    let count: Int
    let label: String
    let onReset: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Big count
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(AppConstants.Color.accent)
                    .shadow(color: AppConstants.Color.accent.opacity(0.5), radius: 12)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
                    .frame(minWidth: 80)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(AppConstants.Color.accent.opacity(0.8))
                    .animation(.easeOut(duration: 0.25), value: label)
            }
            .frame(maxWidth: .infinity)

            // Divider
            Rectangle()
                .fill(AppConstants.Color.accent.opacity(0.2))
                .frame(width: 1, height: 52)

            // Reset button
            Button(action: onReset) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.accent)
                    Text("Reset")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Reset rep count")
        }
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppConstants.Color.accent.opacity(0.35), lineWidth: 1)
                )
        )
        .shadow(color: AppConstants.Color.accent.opacity(0.15), radius: 16, y: 4)
    }
}

// MARK: - Form feedback card

struct FormFeedbackCard: View {
    let feedback: FormFeedback

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Accent indicator bar
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 4, height: 44)
                .shadow(color: accent.opacity(0.6), radius: 6)

            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(feedback.headline)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text(feedback.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent.opacity(0.25), lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.2), value: feedback)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feedback.headline). \(feedback.detail)")
    }

    private var accent: Color {
        switch feedback {
        case .goodForm:
            return AppConstants.Color.accent
        case .notDeepEnough, .kneeAlignmentIssue, .torsoLean,
             .squatStanceTooNarrow, .squatKneesInward,
             .hipsSagging, .hipsRaised, .elbowsTooWide, .pushUpNotLowEnough,
             .lungeKneeForward, .lungeNotDeepEnough, .lungeForwardLean,
             .jumpingJackArmsLow, .jumpingJackLegsNarrow:
            return AppConstants.Color.warn
        case .bodyNotFullyVisible, .lowConfidence:
            return AppConstants.Color.danger
        }
    }

    private var icon: String {
        switch feedback {
        case .goodForm:             return "checkmark.circle.fill"
        case .notDeepEnough:        return "arrow.down.circle.fill"
        case .kneeAlignmentIssue:   return "arrow.left.and.right.circle.fill"
        case .torsoLean:            return "arrow.up.backward.circle.fill"
        case .hipsSagging:          return "arrow.down.circle.fill"
        case .hipsRaised:           return "arrow.up.circle.fill"
        case .elbowsTooWide:        return "arrow.left.and.right.circle.fill"
        case .pushUpNotLowEnough:   return "arrow.down.circle.fill"
        case .lungeKneeForward:     return "figure.walk"
        case .lungeNotDeepEnough:   return "arrow.down.circle.fill"
        case .lungeForwardLean:         return "person.fill.questionmark"
        case .squatStanceTooNarrow:     return "arrow.left.and.right.circle.fill"
        case .squatKneesInward:         return "arrow.left.and.right.circle.fill"
        case .jumpingJackArmsLow:       return "arrow.up.circle.fill"
        case .jumpingJackLegsNarrow:    return "arrow.left.and.right.circle.fill"
        case .bodyNotFullyVisible:      return "person.crop.rectangle.badge.xmark"
        case .lowConfidence:            return "eye.slash.fill"
        }
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
    let feedback: FormFeedback

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

    // Joints that belong to each fault category.
    private static let torsoJoints: Set<VNHumanBodyPoseObservation.JointName> =
        [.neck, .root, .leftShoulder, .rightShoulder, .leftHip, .rightHip]
    private static let kneeJoints: Set<VNHumanBodyPoseObservation.JointName> =
        [.root, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]

    var body: some View {
        Canvas { ctx, _ in
            let map = Dictionary(uniqueKeysWithValues: joints.map { ($0.name, $0) })

            for (a, b) in Self.bones {
                guard
                    let ja = map[a], ja.confidence >= confidenceThreshold,
                    let jb = map[b], jb.confidence >= confidenceThreshold
                else { continue }
                var path = Path()
                path.move(to: convert(ja.point))
                path.addLine(to: convert(jb.point))
                let c = boneColor(a, b)
                ctx.stroke(path, with: .color(c.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 8, lineCap: .round))
                ctx.stroke(path, with: .color(c.opacity(0.95)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            for joint in joints where joint.confidence >= confidenceThreshold {
                let p = convert(joint.point)
                let outer = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
                let inner = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
                let c = jointColor(joint.name)
                ctx.fill(Path(ellipseIn: outer), with: .color(c.opacity(0.3)))
                ctx.fill(Path(ellipseIn: inner), with: .color(c))
            }
        }
    }

    private func boneColor(_ a: VNHumanBodyPoseObservation.JointName,
                            _ b: VNHumanBodyPoseObservation.JointName) -> Color {
        highlighted(a) || highlighted(b) ? .orange : baseTeal
    }

    private func jointColor(_ name: VNHumanBodyPoseObservation.JointName) -> Color {
        highlighted(name) ? .orange : baseTeal
    }

    private func highlighted(_ joint: VNHumanBodyPoseObservation.JointName) -> Bool {
        switch feedback {
        case .torsoLean:               return Self.torsoJoints.contains(joint)
        case .notDeepEnough:           return Self.kneeJoints.contains(joint)
        case .kneeAlignmentIssue:      return [.leftKnee, .rightKnee].contains(joint)
        default:                       return false
        }
    }

    private var baseTeal: Color {
        Color(red: 0x1A/255.0, green: 0xE4/255.0, blue: 0xCB/255.0)
    }

    private func convert(_ p: CGPoint) -> CGPoint {
        // The front camera is already mirrored by the preview layer
        // (isVideoMirrored) together with Vision's .leftMirrored orientation,
        // so the joint coords are in the same space as the displayed image for
        // BOTH cameras. No extra x-flip here — flipping again double-mirrors the
        // front-camera skeleton so it faces the wrong way.
        let y = 1.0 - p.y
        return CGPoint(x: p.x * size.width, y: y * size.height)
    }
}

// MARK: - Live form badge

private struct LiveFormBadge: View {
    let feedback: FormFeedback
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(badgeColor)
                .frame(width: 9, height: 9)
                .shadow(color: badgeColor, radius: pulsing ? 7 : 3)
                .scaleEffect(feedback == .goodForm && pulsing ? 1.2 : 1.0)
                .animation(
                    feedback == .goodForm
                        ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
                        : .default,
                    value: pulsing
                )
            Text(feedback.headline.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.black.opacity(0.62))
                .overlay(Capsule().stroke(badgeColor.opacity(0.55), lineWidth: 1))
        )
        .shadow(color: badgeColor.opacity(0.3), radius: 8)
        .animation(.easeOut(duration: 0.25), value: feedback)
        .onAppear { pulsing = true }
    }

    private var badgeColor: Color {
        switch feedback {
        case .goodForm:                         return .green
        case .bodyNotFullyVisible, .lowConfidence: return Color(red: 1, green: 0.3, blue: 0.3)
        default:                                return .orange
        }
    }
}

// MARK: - Session History Sheet

private struct FormCheckHistorySheet: View {
    let sets: [FormCheckSet]
    let totalCalories: Double
    @Environment(\.dismiss) private var dismiss

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if sets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.stand")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No sets recorded yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Complete an exercise and switch to another\nto save your first set.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        // Total summary
                        Section {
                            HStack {
                                Label("Total Calories", systemImage: "flame.fill")
                                    .foregroundStyle(.orange)
                                Spacer()
                                Text(String(format: "%.1f kcal", totalCalories))
                                    .font(.system(size: 16, weight: .bold))
                            }
                            HStack {
                                Label("Sets Completed", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Spacer()
                                Text("\(sets.count)")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        } header: {
                            Text("Session Summary")
                        }

                        // Individual sets
                        Section {
                            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                                HStack(spacing: 14) {
                                    Image(systemName: set.exercise.systemImage)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 40, height: 40)
                                        .background(Color.teal, in: RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(set.exercise.rawValue)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("\(set.reps) reps · \(String(format: "%.1f kcal", set.calories))")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(Self.timeFormatter.string(from: set.completedAt))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text("Sets")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Form Check History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
