@preconcurrency import AVFoundation
import CoreMediaIO
import Foundation

struct IPhoneScreenDevice: Identifiable {
    let captureDevice: AVCaptureDevice

    var id: String { captureDevice.uniqueID }
    var name: String { captureDevice.localizedName }
}

@MainActor
final class IPhoneScreenCaptureService: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()

    @Published private(set) var devices: [IPhoneScreenDevice] = []
    @Published private(set) var selectedDeviceName: String?
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var videoSize = CGSize(width: 390, height: 844)

    var onCaptureStateChanged: ((Bool) -> Void)?

    private var notificationTokens: [NSObjectProtocol] = []
    private var isActivated = false
    private var selectedDeviceID: String?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "com.example.RecordScreen.iPhoneScreenVideoOutput")
    private nonisolated let frameDelivery = VideoFrameDelivery()

    override init() {
        super.init()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func activate() {
        guard !isActivated else { return }
        isActivated = true

        do {
            try allowScreenCaptureDevices()
            warmUpDeviceDiscovery()
            observeDeviceChanges()
            AppLog.camera.info("Enabled USB iPhone screen-capture device discovery.")
        } catch {
            report(error)
        }
    }

    func refreshDevices() async {
        activate()

        do {
            try await requestCaptureAccess()
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .muxed,
                position: .unspecified
            )
            devices = discoverySession.devices.map(IPhoneScreenDevice.init(captureDevice:))
            if let selectedDeviceID, !devices.contains(where: { $0.id == selectedDeviceID }) {
                AppLog.camera.notice("The active USB iPhone screen device disconnected.")
                stop()
            }
            AppLog.camera.info("Found \(self.devices.count, privacy: .public) USB iPhone screen-capture device(s).")
        } catch {
            report(error)
        }
    }

    func start(using device: IPhoneScreenDevice) throws {
        guard device.captureDevice.isConnected else {
            throw IPhoneScreenCaptureError.deviceDisconnected
        }

        stop()
        captureSession.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device.captureDevice)
            guard captureSession.canAddInput(input) else {
                throw IPhoneScreenCaptureError.inputUnavailable
            }
            captureSession.addInput(input)
            captureSession.sessionPreset = .high
            if captureSession.canAddOutput(videoOutput) {
                videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
                captureSession.addOutput(videoOutput)
            } else {
                AppLog.camera.notice("USB iPhone screen preview will use the device format because a video output could not be added.")
            }
            captureSession.commitConfiguration()
            captureSession.startRunning()
            let dimensions = CMVideoFormatDescriptionGetDimensions(device.captureDevice.activeFormat.formatDescription)
            videoSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
            selectedDeviceName = device.name
            selectedDeviceID = device.id
            isCapturing = true
            errorMessage = nil
            onCaptureStateChanged?(true)
            AppLog.camera.info("Started USB iPhone screen preview: \(device.name, privacy: .public).")
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
        selectedDeviceName = nil
        selectedDeviceID = nil
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

    private func allowScreenCaptureDevices() throws {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
        guard status == noErr else {
            throw IPhoneScreenCaptureError.enableScreenCaptureFailed(status)
        }
    }

    private func warmUpDeviceDiscovery() {
        _ = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        ).devices
    }

    private func observeDeviceChanges() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: .AVCaptureDeviceWasConnected,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshDevices()
                }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: .AVCaptureDeviceWasDisconnected,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshDevices()
                }
            }
        )
    }

    private func requestCaptureAccess() async throws {
        try await requestAccess(for: .video)
        try await requestAccess(for: .audio)
    }

    private func requestAccess(for mediaType: AVMediaType) async throws {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: mediaType) else {
                throw IPhoneScreenCaptureError.accessDenied(mediaType)
            }
        case .denied, .restricted:
            throw IPhoneScreenCaptureError.accessDenied(mediaType)
        @unknown default:
            throw IPhoneScreenCaptureError.accessDenied(mediaType)
        }
    }

    private func report(_ error: Error) {
        AppLog.camera.error("USB iPhone screen capture failed: \(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription
    }
}

extension IPhoneScreenCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
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

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        guard size.width > 0, size.height > 0 else { return }

        Task { @MainActor [weak self] in
            guard self?.videoSize != size else { return }
            self?.videoSize = size
            AppLog.camera.info("Updated USB iPhone screen video size to \(Int(size.width), privacy: .public)x\(Int(size.height), privacy: .public).")
        }
    }
}

private enum IPhoneScreenCaptureError: LocalizedError {
    case accessDenied(AVMediaType)
    case deviceDisconnected
    case enableScreenCaptureFailed(OSStatus)
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case let .accessDenied(mediaType):
            "\(mediaType.rawValue.capitalized) access is required to capture an iPhone screen."
        case .deviceDisconnected:
            "The selected iPhone screen is no longer connected."
        case let .enableScreenCaptureFailed(status):
            "macOS could not enable USB iPhone screen capture (OSStatus \(status))."
        case .inputUnavailable:
            "The selected iPhone screen could not be added to the capture session."
        }
    }
}
