import AVFoundation
import CoreGraphics
import Foundation
import UIKit
import Vision

struct FormCheckSet: Identifiable {
    let id = UUID()
    let exercise: DetectedExercise
    let reps: Int
    let calories: Double
    let completedAt: Date
}

/// A single detected joint in Vision-normalized space.
/// point: Vision coords (origin bottom-left, 0…1). confidence: 0…1.
struct DetectedJoint: Equatable {
    let name: VNHumanBodyPoseObservation.JointName
    let point: CGPoint
    let confidence: Float
}

/// Drives the AVCaptureSession + Vision body-pose pipeline.
///
/// Threading model:
///   - @Published properties are published on the main thread (dispatched via Task/@MainActor).
///   - The class itself is NOT @MainActor so session-queue closures and the
///     nonisolated delegate method can freely access session objects and helpers.
///   - `frontCameraFlag` is a cross-thread mirror for `usingFrontCamera`,
///     protected by NSLock.
final class PoseDetectionViewModel: NSObject, ObservableObject {

    // MARK: Published (always mutated on main thread via Task { @MainActor })

    @Published var joints: [DetectedJoint] = []
    @Published var isTracking = false
    @Published var permissionDenied = false
    @Published var usingFrontCamera = true
    @Published var errorMessage: String?
    @Published var detectedExercise: DetectedExercise = .unknown
    @Published var formFeedback: FormFeedback = .bodyNotFullyVisible
    @Published var viewpoint: Viewpoint = .unknown
    @Published var repCount = 0
    @Published var sessionSets: [FormCheckSet] = []
    @Published var totalSessionCalories: Double = 0

    // MARK: Session objects (accessed on sessionQueue only after setup)

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "PoseDetection.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var currentInput: AVCaptureDeviceInput?

    // MARK: Analysis engine
    private let engine = ExerciseAnalysisEngine()
    let confidenceThreshold: Float = 0.3

    // Cross-thread mirror of `usingFrontCamera`, read from the capture queue.
    private let flagLock = NSLock()
    private var frontCameraFlag = true

    // MARK: Voice coaching (main-thread only)
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenFeedback: FormFeedback?
    private var lastSpeechTime: Date = .distantPast
    private var lastAnnouncedRep = 0
    private var lastGoodFormRepMilestone = 0
    private var lastAnnouncedExercise: DetectedExercise = .unknown
    private var pendingExerciseName: String? = nil
    @Published var voiceMuted = false {
        didSet { if voiceMuted { speechSynthesizer.stopSpeaking(at: .immediate) } }
    }

    // MARK: Haptics (main-thread only)
    private let repHaptic   = UIImpactFeedbackGenerator(style: .medium)
    private let errorHaptic = UINotificationFeedbackGenerator()

    // MARK: Lifecycle (called from SwiftUI, which is on MainActor)

    func onAppear() {
        Task { await requestPermissionAndStart() }
    }

    func onDisappear() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        Task { @MainActor in
            self.saveSetIfNeeded(exercise: self.detectedExercise, reps: self.repCount)
            self.lastAnnouncedExercise = .unknown
        }
    }

    func resetCount() {
        // Capture before engine.resetCount() so incoming camera frames can't
        // zero out repCount before our save Task runs.
        let savedExercise = detectedExercise
        let savedReps     = repCount
        engine.resetCount()
        Task { @MainActor in
            self.saveSetIfNeeded(exercise: savedExercise, reps: savedReps)
            self.repCount = 0
            self.lastAnnouncedRep = 0
            self.lastGoodFormRepMilestone = 0
            self.pendingExerciseName = nil
            self.lastSpokenFeedback = nil
            self.lastSpeechTime = .distantPast
            self.speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    func flipCamera() {
        // Toggle the published property on the main thread.
        Task { @MainActor in
            self.usingFrontCamera.toggle()
            let next = self.usingFrontCamera
            self.setFlag(next)
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.session.beginConfiguration()
                if let old = self.currentInput { self.session.removeInput(old) }
                self.addCameraInput(front: next)
                self.session.commitConfiguration()
            }
        }
    }

    // MARK: Permission

    private func requestPermissionAndStart() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                startSession()
            } else {
                await MainActor.run { self.permissionDenied = true }
            }
        default:
            await MainActor.run { self.permissionDenied = true }
        }
    }

    // MARK: Session setup

    private func startSession() {
        // Read the published value before leaving the calling context.
        let wantFront = usingFrontCamera
        setFlag(wantFront)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            self.addCameraInput(front: wantFront)
            if self.session.canAddOutput(self.videoOutput) {
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                self.session.addOutput(self.videoOutput)
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    // MARK: Camera input (called on sessionQueue)

    private func addCameraInput(front: Bool) {
        let position: AVCaptureDevice.Position = front ? .front : .back
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video,
                                                 position: position),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            Task { @MainActor in self.errorMessage = "Camera unavailable" }
            return
        }
        session.addInput(input)
        currentInput = input
    }

    // MARK: Flag helpers

    private func setFlag(_ value: Bool) {
        flagLock.lock(); frontCameraFlag = value; flagLock.unlock()
    }

    private func readFlag() -> Bool {
        flagLock.lock(); defer { flagLock.unlock() }; return frontCameraFlag
    }

    // MARK: Session history

    @MainActor
    private func saveSetIfNeeded(exercise: DetectedExercise, reps: Int) {
        guard exercise != .unknown, reps > 0 else { return }
        let calories = Double(reps) * exercise.caloriesPerRep
        let set = FormCheckSet(exercise: exercise, reps: reps, calories: calories, completedAt: Date())
        sessionSets.append(set)
        totalSessionCalories += calories
    }

    // MARK: Voice coaching (must be called on main thread)

    @MainActor
    private func announceExerciseIfChanged(_ exercise: DetectedExercise) {
        guard exercise != lastAnnouncedExercise else { return }
        lastAnnouncedExercise = exercise
        // Queue the name to be spoken with the first rep — avoids false "Squat detected"
        // just from standing still in frame.
        pendingExerciseName = exercise != .unknown ? exercise.rawValue : nil
    }

    @MainActor
    private func speakIfNeeded(feedback: FormFeedback, repCount: Int) {
        if repCount < lastAnnouncedRep { lastAnnouncedRep = repCount }

        // Completed rep: haptic always fires, voice only when unmuted.
        if repCount > lastAnnouncedRep {
            lastAnnouncedRep = repCount
            repHaptic.impactOccurred()
            if !voiceMuted {
                if let name = pendingExerciseName {
                    speak("\(name). \(repCount).", interrupt: true)
                } else {
                    speak("\(repCount)", interrupt: true)
                }
            }
            pendingExerciseName = nil
            return
        }

        let prompt = feedback.voicePrompt
        guard !prompt.isEmpty else { return }

        let now = Date()

        switch feedback {

        case .goodForm:
            // Say "Great form" only at every 5-rep milestone, OR once per minute — never spam.
            let hitMilestone = repCount > 0 && repCount % 5 == 0 && repCount != lastGoodFormRepMilestone
            guard hitMilestone || now.timeIntervalSince(lastSpeechTime) >= 60 else { return }
            guard voiceMuted || !speechSynthesizer.isSpeaking else { return }
            if hitMilestone { lastGoodFormRepMilestone = repCount }
            if feedback != lastSpokenFeedback { errorHaptic.notificationOccurred(.success) }
            lastSpokenFeedback = feedback
            lastSpeechTime = now
            if !voiceMuted { speak(prompt, interrupt: false) }

        case .bodyNotFullyVisible:
            // Repeat every 10 seconds so the user knows to reposition.
            guard now.timeIntervalSince(lastSpeechTime) >= 10 else { return }
            guard voiceMuted || !speechSynthesizer.isSpeaking else { return }
            lastSpokenFeedback = feedback
            lastSpeechTime = now
            if !voiceMuted { speak(prompt, interrupt: false) }

        default:
            // Form warnings: repeat every 4 seconds while the fault persists.
            guard feedback != lastSpokenFeedback || now.timeIntervalSince(lastSpeechTime) >= 4 else { return }
            if !voiceMuted && speechSynthesizer.isSpeaking { return }
            if feedback != lastSpokenFeedback { errorHaptic.notificationOccurred(.warning) }
            lastSpokenFeedback = feedback
            lastSpeechTime = now
            if !voiceMuted { speak(prompt, interrupt: false) }
        }
    }

    private func speak(_ text: String, interrupt: Bool) {
        // Use .playback so speech plays even when the silent switch is on.
        try? AVAudioSession.sharedInstance().setCategory(.playback,
                                                         mode: .default,
                                                         options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        if interrupt { speechSynthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.1
        utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PoseDetectionViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // CRITICAL: drain Vision/CoreML/pixel-buffer temporaries every frame.
        // Without this, autoreleased objects pile up faster than the dispatch
        // queue drains them → memory balloons → iOS jetsam force-quits the app.
        // This is the root cause of the intermittent "random" crashes.
        autoreleasepool {
            processFrame(sampleBuffer)
        }
    }

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Vision needs the correct image orientation so joint coordinates map
        // to the right position in the frame.
        // Portrait UI: back camera produces .right frames; front produces .leftMirrored.
        let isFront = readFlag()
        let orientation: CGImagePropertyOrientation = isFront ? .leftMirrored : .right

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([poseRequest])
            guard let obs = poseRequest.results?.first else {
                engine.feedObservation(nil)
                Task { @MainActor in
                    self.joints = []
                    self.isTracking = false
                    self.detectedExercise = .unknown
                    self.formFeedback = .bodyNotFullyVisible
                    self.viewpoint = .unknown
                }
                return
            }
            let recognized = try obs.recognizedPoints(.all)
            let detected: [DetectedJoint] = recognized.compactMap { name, pt in
                guard pt.confidence > 0 else { return nil }
                return DetectedJoint(name: name,
                                     point: CGPoint(x: pt.location.x, y: pt.location.y),
                                     confidence: pt.confidence)
            }
            // Feed raw pose observation into the ML sliding window.
            engine.feedObservation(obs)
            // All analysis (detection + form + rep counting) happens on the
            // capture queue so the main thread only receives final values.
            let result = engine.analyze(joints: detected,
                                        confidenceThreshold: confidenceThreshold)
            Task { @MainActor in
                // Save completed set before state updates (self.detectedExercise still holds old value)
                if result.exercise != self.detectedExercise {
                    self.saveSetIfNeeded(exercise: self.detectedExercise, reps: self.repCount)
                }
                self.joints = detected
                self.isTracking = detected.contains { $0.confidence >= self.confidenceThreshold }
                self.detectedExercise = result.exercise
                self.formFeedback = result.feedback
                self.repCount = result.repCount
                self.viewpoint = result.viewpoint
                self.announceExerciseIfChanged(result.exercise)
                self.speakIfNeeded(feedback: result.feedback, repCount: result.repCount)
            }
        } catch {
            Task { @MainActor in
                self.errorMessage = error.localizedDescription
                self.isTracking = false
                self.formFeedback = .lowConfidence
            }
        }
    }
}
