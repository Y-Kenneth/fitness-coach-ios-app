import AVFoundation
import CoreGraphics
import Foundation
import Vision

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

    // MARK: Session objects (accessed on sessionQueue only after setup)

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "PoseDetection.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var currentInput: AVCaptureDeviceInput?

    // Cross-thread mirror of `usingFrontCamera`, read from the capture queue.
    private let flagLock = NSLock()
    private var frontCameraFlag = true

    // MARK: Lifecycle (called from SwiftUI, which is on MainActor)

    func onAppear() {
        Task { await requestPermissionAndStart() }
    }

    func onDisappear() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
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
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PoseDetectionViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
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
                Task { @MainActor in
                    self.joints = []; self.isTracking = false
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
            Task { @MainActor in
                self.joints = detected
                self.isTracking = detected.contains { $0.confidence >= 0.3 }
            }
        } catch {
            Task { @MainActor in
                self.errorMessage = error.localizedDescription
                self.isTracking = false
            }
        }
    }
}
