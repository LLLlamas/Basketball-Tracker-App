import AVFoundation
import Combine

enum CameraError: Error {
    case noDevice
    case inputFailed
    case notAuthorized
}

final class CameraManager: ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "shottracker.camera.session")
    private let frameQueue = DispatchQueue(label: "shottracker.camera.frames", qos: .userInitiated)

    @Published private(set) var isAuthorized = false
    @Published private(set) var isConfigured = false

    private var frameDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?

    /// Install a frame-buffer delegate. Typically called once with FrameProcessor
    /// before `configure()`.
    func setFrameDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        self.frameDelegate = delegate
        videoOutput.setSampleBufferDelegate(delegate, queue: frameQueue)
    }

    @MainActor
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
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureSessionOnQueue()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        await MainActor.run { self.isConfigured = true }
    }

    private func configureSessionOnQueue() throws {
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
        if let frameDelegate {
            videoOutput.setSampleBufferDelegate(frameDelegate, queue: frameQueue)
        }
        guard session.canAddOutput(videoOutput) else { throw CameraError.inputFailed }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    func start() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }
}
