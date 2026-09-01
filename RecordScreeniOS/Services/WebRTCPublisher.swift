import AVFoundation
import Foundation
@preconcurrency import WebRTC

@MainActor
final class WebRTCPublisher: NSObject, ObservableObject, StreamPublisher {
    @Published private(set) var state: StreamConnectionState = .idle
    @Published private(set) var localVideoTrack: RTCVideoTrack?

    var signalSender: ((SignalingMessage) throws -> Void)?
    var onError: ((Error) -> Void)?

    private let streamID = "recordscreen-video"
    private var factory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var queuedRemoteCandidates: [RTCIceCandidate] = []
    private var hasRemoteDescription = false
    private var isPublishing = false

    func startPublishing(configuration: StreamConfiguration) async throws {
        guard !isPublishing else { return }
        guard signalSender != nil else {
            throw SignalingError.handshakeIncomplete
        }

        state = .preparing
        AppLog.webRTC.info("Preparing iPhone WebRTC publisher.")
        do {
            let factory = RTCPeerConnectionFactory()
            let peerConnection = try makePeerConnection(factory: factory)
            let source = factory.videoSource()
            let capturer = RTCCameraVideoCapturer(delegate: source)
            let videoTrack = factory.videoTrack(with: source, trackId: streamID)

            self.factory = factory
            self.peerConnection = peerConnection
            self.videoCapturer = capturer
            self.localVideoTrack = videoTrack
            isPublishing = true

            peerConnection.add(videoTrack, streamIds: [streamID])
            try startRearCameraCapture(with: capturer, configuration: configuration)
            AppLog.webRTC.info("Started iPhone WebRTC rear-camera capture.")

            let offer = try await createOffer(on: peerConnection)
            try await setLocalDescription(offer, on: peerConnection)
            AppLog.webRTC.info("Created and set iPhone WebRTC offer.")
            try send(.offer(sdp: offer.sdp))
            state = .connecting
        } catch {
            fail(error)
            throw error
        }
    }

    func stopPublishing() {
        tearDown()
        state = .idle
    }

    func handle(_ message: SignalingMessage) async throws {
        guard let peerConnection else {
            throw WebRTCPublisherError.peerConnectionUnavailable
        }

        switch message.kind {
        case .answer:
            guard let sdp = message.sdp else {
                throw SignalingError.malformedMessage
            }
            let answer = RTCSessionDescription(type: .answer, sdp: sdp)
            try await setRemoteDescription(answer, on: peerConnection)
            hasRemoteDescription = true
            try await addQueuedCandidates(to: peerConnection)
        case .candidate:
            guard let candidate = message.candidate else {
                throw SignalingError.malformedMessage
            }
            let rtcCandidate = RTCIceCandidate(
                sdp: candidate.sdp,
                sdpMLineIndex: candidate.sdpMLineIndex,
                sdpMid: candidate.sdpMid
            )
            if hasRemoteDescription {
                try await add(candidate: rtcCandidate, to: peerConnection)
            } else {
                queuedRemoteCandidates.append(rtcCandidate)
            }
        case .disconnect:
            stopPublishing()
        case .hello, .ack, .offer:
            throw SignalingError.malformedMessage
        }
    }

    private func makePeerConnection(factory: RTCPeerConnectionFactory) throws -> RTCPeerConnection {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.iceTransportPolicy = .all
        configuration.iceServers = []

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false",
                "DtlsSrtpKeyAgreement": "true"
            ],
            optionalConstraints: nil
        )
        guard let peerConnection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw WebRTCPublisherError.peerConnectionUnavailable
        }
        return peerConnection
    }

    private func startRearCameraCapture(
        with capturer: RTCCameraVideoCapturer,
        configuration: StreamConfiguration
    ) throws {
        guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .back }) else {
            throw WebRTCPublisherError.rearCameraUnavailable
        }
        guard let format = preferredFormat(for: device, resolution: configuration.resolution) else {
            throw WebRTCPublisherError.cameraFormatUnavailable
        }

        let maximumFrameRate = format.videoSupportedFrameRateRanges
            .map(\.maxFrameRate)
            .max() ?? Double(configuration.frameRate)
        let frameRate = max(1, Int(min(Double(configuration.frameRate), maximumFrameRate)))
        capturer.startCapture(with: device, format: format, fps: frameRate)
    }

    private func preferredFormat(
        for device: AVCaptureDevice,
        resolution: StreamConfiguration.Resolution
    ) -> AVCaptureDevice.Format? {
        let preferredSize: (width: Int32, height: Int32) = switch resolution {
        case .hd:
            (1280, 720)
        case .fullHD:
            (1920, 1080)
        }
        return RTCCameraVideoCapturer.supportedFormats(for: device).min { first, second in
            let firstSize = CMVideoFormatDescriptionGetDimensions(first.formatDescription)
            let secondSize = CMVideoFormatDescriptionGetDimensions(second.formatDescription)
            let firstDistance = abs(firstSize.width - preferredSize.width) + abs(firstSize.height - preferredSize.height)
            let secondDistance = abs(secondSize.width - preferredSize.width) + abs(secondSize.height - preferredSize.height)
            return firstDistance < secondDistance
        }
    }

    private func createOffer(on peerConnection: RTCPeerConnection) async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { description, error in
                if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: error ?? WebRTCPublisherError.offerCreationFailed)
                }
            }
        }
    }

    private func setLocalDescription(
        _ description: RTCSessionDescription,
        on peerConnection: RTCPeerConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func setRemoteDescription(
        _ description: RTCSessionDescription,
        on peerConnection: RTCPeerConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func addQueuedCandidates(to peerConnection: RTCPeerConnection) async throws {
        let candidates = queuedRemoteCandidates
        queuedRemoteCandidates.removeAll(keepingCapacity: false)
        for candidate in candidates {
            try await add(candidate: candidate, to: peerConnection)
        }
    }

    private func add(candidate: RTCIceCandidate, to peerConnection: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.add(candidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func send(_ message: SignalingMessage) throws {
        guard let signalSender else {
            throw SignalingError.unavailable
        }
        try signalSender(message)
    }

    private func fail(_ error: Error) {
        AppLog.webRTC.error("iPhone WebRTC failed: \(error.localizedDescription, privacy: .public)")
        tearDown()
        state = .failed(error.localizedDescription)
        onError?(error)
    }

    private func tearDown() {
        videoCapturer?.stopCapture()
        peerConnection?.close()
        queuedRemoteCandidates.removeAll(keepingCapacity: false)
        hasRemoteDescription = false
        isPublishing = false
        videoCapturer = nil
        localVideoTrack = nil
        peerConnection = nil
        factory = nil
    }
}

extension WebRTCPublisher: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        AppLog.webRTC.info("iPhone WebRTC negotiation was requested.")
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            self?.handleICEConnectionState(newState)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let message = SignalingMessage.candidate(ICECandidateMessage(
            sdp: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        ))
        Task { @MainActor [weak self] in
            self?.sendLocalCandidate(message)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            self?.handlePeerConnectionState(newState)
        }
    }
}

private extension WebRTCPublisher {
    func handleICEConnectionState(_ newState: RTCIceConnectionState) {
        AppLog.webRTC.info("iPhone ICE connection state: \(String(describing: newState), privacy: .public).")
        switch newState {
        case .connected, .completed:
            state = .connected
        case .disconnected:
            if isPublishing {
                state = .reconnecting
            }
        case .failed:
            fail(WebRTCPublisherError.iceConnectionFailed)
        case .closed:
            break
        case .new, .checking, .count:
            break
        @unknown default:
            break
        }
    }

    func sendLocalCandidate(_ message: SignalingMessage) {
        AppLog.webRTC.info("iPhone generated a local ICE candidate.")
        do {
            try send(message)
        } catch {
            fail(error)
        }
    }

    func handlePeerConnectionState(_ newState: RTCPeerConnectionState) {
        if newState == .failed {
            fail(WebRTCPublisherError.iceConnectionFailed)
        }
    }
}

private enum WebRTCPublisherError: LocalizedError {
    case peerConnectionUnavailable
    case rearCameraUnavailable
    case cameraFormatUnavailable
    case offerCreationFailed
    case iceConnectionFailed

    var errorDescription: String? {
        switch self {
        case .peerConnectionUnavailable:
            "Could not create a WebRTC peer connection."
        case .rearCameraUnavailable:
            "The rear camera is unavailable."
        case .cameraFormatUnavailable:
            "The rear camera does not support a usable video format."
        case .offerCreationFailed:
            "Could not create the WebRTC offer."
        case .iceConnectionFailed:
            "The WebRTC video connection failed."
        }
    }
}
