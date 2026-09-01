@preconcurrency import AVFoundation
import Foundation

struct ContinuityCameraDevice: Identifiable {
    let captureDevice: AVCaptureDevice

    var id: String { captureDevice.uniqueID }
    var name: String { captureDevice.localizedName }
}

@MainActor
final class ContinuityCameraService: ObservableObject {
    let captureSession = AVCaptureSession()

    @Published private(set) var devices: [ContinuityCameraDevice] = []
    @Published private(set) var selectedDeviceName: String?
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?

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
            captureSession.commitConfiguration()
            captureSession.startRunning()
            AVCaptureDevice.userPreferredCamera = device.captureDevice
            selectedDeviceName = device.name
            isCapturing = true
            errorMessage = nil
            AppLog.camera.info("Started Continuity Camera preview: \(device.name, privacy: .public).")
        } catch {
            captureSession.commitConfiguration()
            report(error)
            throw error
        }
    }

    func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        captureSession.inputs.forEach(captureSession.removeInput)
        selectedDeviceName = nil
        isCapturing = false
    }

    func dismissError() {
        errorMessage = nil
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
}

private enum ContinuityCameraError: LocalizedError {
    case accessDenied
    case deviceDisconnected
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Camera access is required to use an iPhone as a Continuity Camera."
        case .deviceDisconnected:
            "The selected iPhone camera is no longer connected."
        case .inputUnavailable:
            "The selected iPhone camera could not be added to the capture session."
        }
    }
}
