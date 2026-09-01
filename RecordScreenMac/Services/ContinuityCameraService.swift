@preconcurrency import AVFoundation
import Foundation

struct ContinuityCameraDevice: Identifiable {
    let captureDevice: AVCaptureDevice

    var id: String { captureDevice.uniqueID }
    var name: String { captureDevice.localizedName }
}

@MainActor
final class ContinuityCameraService: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()

    @Published private(set) var devices: [ContinuityCameraDevice] = []
    @Published private(set) var selectedDeviceName: String?
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?

    var onCaptureStateChanged: ((Bool) -> Void)?

    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "com.example.RecordScreen.continuityCameraVideoOutput")
    private nonisolated let frameDelivery = VideoFrameDelivery()
    private var disconnectObserver: NSObjectProtocol?

    override init() {
        super.init()
    }

    deinit {
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
        }
    }

    func refreshDevices() async {
        do {
            try await requestCameraAccess()
            // Apple exposes compatible iPhone Continuity Cameras as external devices.
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .video,
                position: .unspecified
            )
            devices = discoverySession.devices
                .map(ContinuityCameraDevice.init(captureDevice:))
            AppLog.camera.info("Found \(self.devices.count, privacy: .public) external video device(s), including compatible iPhone Continuity Cameras.")
        } catch {
            report(error)
        }
    }

    func start(using device: ContinuityCameraDevice) throws {
        guard device.captureDevice.isConnected else {
            throw ContinuityCameraError.deviceDisconnected
        }

        stop()
        captureSession.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device.captureDevice)
            guard captureSession.canAddInput(input) else {
                throw ContinuityCameraError.inputUnavailable
            }
            captureSession.addInput(input)
            captureSession.sessionPreset = .high
            guard captureSession.canAddOutput(videoOutput) else {
                throw ContinuityCameraError.outputUnavailable
            }
            videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            captureSession.addOutput(videoOutput)
            captureSession.commitConfiguration()
            captureSession.startRunning()
            AVCaptureDevice.userPreferredCamera = device.captureDevice
            selectedDeviceName = device.name
            isCapturing = true
            errorMessage = nil
            observeDisconnection(of: device.captureDevice)
            onCaptureStateChanged?(true)
            AppLog.camera.info("Started Continuity Camera preview: \(device.name, privacy: .public).")
        } catch {
            captureSession.commitConfiguration()
            report(error)
            throw error
        }
    }

    func stop() {
        let wasCapturing = isCapturing
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        captureSession.inputs.forEach(captureSession.removeInput)
        captureSession.outputs.forEach(captureSession.removeOutput)
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
            self.disconnectObserver = nil
        }
        selectedDeviceName = nil
        isCapturing = false
        if wasCapturing {
            onCaptureStateChanged?(false)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func setVideoFrameHandler(_ handler: VideoFrameHandler?) {
        frameDelivery.setHandler(handler)
    }

    private func requestCameraAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw ContinuityCameraError.accessDenied
            }
        case .denied, .restricted:
            throw ContinuityCameraError.accessDenied
        @unknown default:
            throw ContinuityCameraError.accessDenied
        }
    }

    private func report(_ error: Error) {
        AppLog.camera.error("Continuity Camera failed: \(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription
    }

    private func observeDisconnection(of device: AVCaptureDevice) {
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: device,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                AppLog.camera.notice("The active Continuity Camera device disconnected.")
                self?.stop()
            }
        }
    }
}

extension ContinuityCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else {
            return
        }
        frameDelivery.deliver(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }
}

private enum ContinuityCameraError: LocalizedError {
    case accessDenied
    case deviceDisconnected
    case inputUnavailable
    case outputUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Camera access is required to use an iPhone as a Continuity Camera."
        case .deviceDisconnected:
            "The selected iPhone camera is no longer connected."
        case .inputUnavailable:
            "The selected iPhone camera could not be added to the capture session."
        case .outputUnavailable:
            "The selected iPhone camera could not provide video frames for recording."
        }
    }
}
