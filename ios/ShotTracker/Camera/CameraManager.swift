import AVFoundation
import Combine

enum CameraError: Error {
    case noDevice
    case inputFailed
    case notAuthorized
}

@MainActor
final class CameraManager: ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "shottracker.camera.session")
    private let frameQueue = DispatchQueue(label: "shottracker.camera.frames", qos: .userInitiated)

    @Published private(set) var isAuthorized = false
    @Published private(set) var isConfigured = false

    func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            return granted
        default:
            isAuthorized = false
            return false
        }
    }

    func configure() async throws {
        guard !isConfigured else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureSession()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        isConfigured = true
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1920x1080

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraError.noDevice
        }

        try device.lockForConfiguration()
        let thirtyFPS = CMTime(value: 1, timescale: 30)
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
            $0.minFrameDuration <= thirtyFPS && $0.maxFrameDuration >= thirtyFPS
        }) {
            device.activeVideoMinFrameDuration = thirtyFPS
            device.activeVideoMaxFrameDuration = thirtyFPS
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.inputFailed }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // Frame delegate left nil until Phase 1 (detection pipeline).
        guard session.canAddOutput(videoOutput) else { throw CameraError.inputFailed }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}
