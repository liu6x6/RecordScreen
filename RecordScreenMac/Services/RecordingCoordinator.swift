@preconcurrency import AVFoundation
import Foundation
@preconcurrency import WebRTC

enum RecordingSource: Sendable {
    case webRTC
    case continuityCamera
    case iPhoneScreen

    var title: String {
        switch self {
        case .webRTC:
            "WebRTC Stream"
        case .continuityCamera:
            "iPhone Camera"
        case .iPhoneScreen:
            "iPhone Screen"
        }
    }
}

@MainActor
final class RecordingCoordinator: ObservableObject {
    let recordingService = RecordingService()

    private let receiver: ReceiverService
    private let continuityCamera: ContinuityCameraService
    private let screenCapture: IPhoneScreenCaptureService
    private let webRTCFrameRenderer = WebRTCRecordingRenderer()
    private var attachedWebRTCTrack: RTCVideoTrack?
    private var activeSource: RecordingSource?

    init(
        receiver: ReceiverService,
        continuityCamera: ContinuityCameraService,
        screenCapture: IPhoneScreenCaptureService
    ) {
        self.receiver = receiver
        self.continuityCamera = continuityCamera
        self.screenCapture = screenCapture

        recordingService.onStateChanged = { [weak self] _ in
            self?.objectWillChange.send()
            self?.recordingStateChanged()
        }
        webRTCFrameRenderer.setFrameHandler { [weak self] pixelBuffer, presentationTime in
            Task { @MainActor [weak self] in
                self?.append(
                    pixelBuffer: pixelBuffer,
                    presentationTime: presentationTime,
                    from: .webRTC
                )
            }
        }
        receiver.onRemoteVideoTrackChanged = { [weak self] track in
            self?.remoteVideoTrackChanged(track)
        }
        continuityCamera.onCaptureStateChanged = { [weak self] isCapturing in
            self?.captureStateChanged(isCapturing, for: .continuityCamera)
        }
        screenCapture.onCaptureStateChanged = { [weak self] isCapturing in
            self?.captureStateChanged(isCapturing, for: .iPhoneScreen)
        }
    }

    func startRecording(from source: RecordingSource) async {
        guard !recordingService.state.isBusy else {
            AppLog.recording.notice("Ignored a request to start a second recording.")
            return
        }
        guard sourceIsAvailable(source) else {
            recordingService.reportFailure("\(source.title) is not available to record.")
            return
        }
        activeSource = source
        guard await recordingService.beginRecording() else { return }
        guard activeSource == source else { return }
        guard sourceIsAvailable(source) else {
            recordingService.reportFailure("\(source.title) disappeared before recording could start.")
            return
        }

        attachFrameSource(source)
    }

    func stopRecording() async {
        guard let source = activeSource else {
            await recordingService.finishRecording()
            return
        }
        activeSource = nil
        detachFrameSource(source)
        await recordingService.finishRecording()
    }

    func stopRecording(ifActiveSource source: RecordingSource) async {
        guard activeSource == source else { return }
        await stopRecording()
    }

    func isRecording(from source: RecordingSource) -> Bool {
        activeSource == source && recordingService.state.isBusy
    }

    private func sourceIsAvailable(_ source: RecordingSource) -> Bool {
        switch source {
        case .webRTC:
            receiver.remoteVideoTrack != nil
        case .continuityCamera:
            continuityCamera.isCapturing
        case .iPhoneScreen:
            screenCapture.isCapturing
        }
    }

    private func attachFrameSource(_ source: RecordingSource) {
        switch source {
        case .webRTC:
            attachWebRTCTrack(receiver.remoteVideoTrack)
        case .continuityCamera:
            continuityCamera.setVideoFrameHandler(frameHandler(for: source))
        case .iPhoneScreen:
            screenCapture.setVideoFrameHandler(frameHandler(for: source))
        }
        AppLog.recording.info("Attached \(source.title, privacy: .public) to the recording pipeline.")
    }

    private func detachFrameSource(_ source: RecordingSource) {
        switch source {
        case .webRTC:
            if let attachedWebRTCTrack {
                attachedWebRTCTrack.remove(webRTCFrameRenderer)
            }
            attachedWebRTCTrack = nil
        case .continuityCamera:
            continuityCamera.setVideoFrameHandler(nil)
        case .iPhoneScreen:
            screenCapture.setVideoFrameHandler(nil)
        }
        AppLog.recording.info("Detached \(source.title, privacy: .public) from the recording pipeline.")
    }

    private func frameHandler(for source: RecordingSource) -> VideoFrameHandler {
        { [weak self] pixelBuffer, presentationTime in
            Task { @MainActor [weak self] in
                self?.append(
                    pixelBuffer: pixelBuffer,
                    presentationTime: presentationTime,
                    from: source
                )
            }
        }
    }

    private func append(
        pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        from source: RecordingSource
    ) {
        guard activeSource == source else { return }
        recordingService.append(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }

    private func remoteVideoTrackChanged(_ track: RTCVideoTrack?) {
        guard activeSource == .webRTC, recordingService.state.isActive else { return }
        guard let track else {
            Task { [weak self] in
                await self?.stopRecording()
            }
            return
        }
        attachWebRTCTrack(track)
    }

    private func attachWebRTCTrack(_ track: RTCVideoTrack?) {
        guard let track else {
            recordingService.reportFailure("The WebRTC video track is unavailable.")
            if activeSource == .webRTC {
                activeSource = nil
                detachFrameSource(.webRTC)
            }
            return
        }
        guard attachedWebRTCTrack !== track else { return }
        if let attachedWebRTCTrack {
            attachedWebRTCTrack.remove(webRTCFrameRenderer)
        }
        track.add(webRTCFrameRenderer)
        attachedWebRTCTrack = track
    }

    private func captureStateChanged(_ isCapturing: Bool, for source: RecordingSource) {
        guard !isCapturing, activeSource == source else { return }
        Task { [weak self] in
            await self?.stopRecording()
        }
    }

    private func recordingStateChanged() {
        guard case .failed = recordingService.state, let activeSource else { return }
        self.activeSource = nil
        detachFrameSource(activeSource)
    }
}
