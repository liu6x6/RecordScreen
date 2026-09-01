@preconcurrency import AVFoundation
import Foundation

@MainActor
final class CameraCaptureService: ObservableObject {
    let captureSession = AVCaptureSession()
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isConfigured = false

    func requestAccessAndConfigure() async throws {
        if authorizationStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            guard granted else { throw CameraError.accessDenied }
        }

        guard authorizationStatus == .authorized else { throw CameraError.accessDenied }
        configureIfNeeded()
        AppLog.camera.info("Camera preview is configured.")
    }

    func startPreview() {
        guard isConfigured, !captureSession.isRunning else { return }
        AppLog.camera.info("Starting native camera preview.")
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.startRunning()
        }
    }

    func stopPreview() {
        guard captureSession.isRunning else { return }
        AppLog.camera.info("Stopping native camera preview.")
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.stopRunning()
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            AppLog.camera.error("Unable to configure the rear camera for native preview.")
            return
        }

        captureSession.sessionPreset = .hd1920x1080
        captureSession.addInput(input)
        isConfigured = true
    }
}

enum CameraError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "Camera access is required to start a live stream."
    }
}
