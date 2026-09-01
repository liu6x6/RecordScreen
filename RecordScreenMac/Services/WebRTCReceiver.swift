import Foundation
@preconcurrency import WebRTC

@MainActor
final class WebRTCReceiver: NSObject {
    var onLocalCandidate: ((SignalingMessage) -> Void)?
    var onConnectionStateChanged: ((StreamConnectionState) -> Void)?
    var onRemoteVideoTrackChanged: ((RTCVideoTrack?) -> Void)?
    var onError: ((Error) -> Void)?

    private var factory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var queuedRemoteCandidates: [RTCIceCandidate] = []
    private var hasRemoteDescription = false

    func prepare() throws {
        guard peerConnection == nil else { return }

        AppLog.webRTC.info("Preparing Mac WebRTC receiver.")
        let factory = RTCPeerConnectionFactory()
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.iceTransportPolicy = .all
        configuration.iceServers = []

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "true",
                "DtlsSrtpKeyAgreement": "true"
            ],
            optionalConstraints: nil
        )
        guard let peerConnection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw WebRTCReceiverError.peerConnectionUnavailable
        }
        self.factory = factory
        self.peerConnection = peerConnection
    }

    func handle(_ message: SignalingMessage) async throws {
        try prepare()
        guard let peerConnection else {
            throw WebRTCReceiverError.peerConnectionUnavailable
        }

        switch message.kind {
        case .offer:
            AppLog.webRTC.info("Mac received WebRTC offer.")
            guard let sdp = message.sdp else {
                throw SignalingError.malformedMessage
            }
            let offer = RTCSessionDescription(type: .offer, sdp: sdp)
            try await setRemoteDescription(offer, on: peerConnection)
            hasRemoteDescription = true
            try await addQueuedCandidates(to: peerConnection)

            let answer = try await createAnswer(on: peerConnection)
            try await setLocalDescription(answer, on: peerConnection)
            AppLog.webRTC.info("Mac created and set WebRTC answer.")
            onLocalCandidate?(.answer(sdp: answer.sdp))
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
            stop()
        case .hello, .ack, .answer:
            throw SignalingError.malformedMessage
        }
    }

    func stop() {
        peerConnection?.close()
        queuedRemoteCandidates.removeAll(keepingCapacity: false)
        hasRemoteDescription = false
        peerConnection = nil
        factory = nil
        onRemoteVideoTrackChanged?(nil)
    }

    private func createAnswer(on peerConnection: RTCPeerConnection) async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.answer(for: constraints) { description, error in
                if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: error ?? WebRTCReceiverError.answerCreationFailed)
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

    private func report(_ error: Error) {
        AppLog.webRTC.error("Mac WebRTC failed: \(error.localizedDescription, privacy: .public)")
        onError?(error)
    }
}

extension WebRTCReceiver: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let videoTrack = stream.videoTracks.first
        Task { @MainActor [weak self] in
            self?.updateRemoteVideoTrack(videoTrack)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Task { @MainActor [weak self] in
            self?.updateRemoteVideoTrack(nil)
        }
    }

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        AppLog.webRTC.info("Mac WebRTC negotiation was requested.")
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

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams: [RTCMediaStream]
    ) {
        let videoTrack = rtpReceiver.track as? RTCVideoTrack
        Task { @MainActor [weak self] in
            self?.updateRemoteVideoTrack(videoTrack)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            self?.handlePeerConnectionState(newState)
        }
    }
}

private extension WebRTCReceiver {
    func updateRemoteVideoTrack(_ videoTrack: RTCVideoTrack?) {
        AppLog.webRTC.info("Mac remote video track \(videoTrack == nil ? "removed" : "received", privacy: .public).")
        onRemoteVideoTrackChanged?(videoTrack)
    }

    func handleICEConnectionState(_ newState: RTCIceConnectionState) {
        AppLog.webRTC.info("Mac ICE connection state: \(String(describing: newState), privacy: .public).")
        switch newState {
        case .connected, .completed:
            onConnectionStateChanged?(.connected)
        case .disconnected:
            onConnectionStateChanged?(.reconnecting)
        case .failed:
            report(WebRTCReceiverError.iceConnectionFailed)
        case .closed:
            break
        case .new, .checking, .count:
            break
        @unknown default:
            break
        }
    }

    func sendLocalCandidate(_ message: SignalingMessage) {
        AppLog.webRTC.info("Mac generated a local ICE candidate.")
        onLocalCandidate?(message)
    }

    func handlePeerConnectionState(_ newState: RTCPeerConnectionState) {
        if newState == .failed {
            report(WebRTCReceiverError.iceConnectionFailed)
        }
    }
}

private enum WebRTCReceiverError: LocalizedError {
    case peerConnectionUnavailable
    case answerCreationFailed
    case iceConnectionFailed

    var errorDescription: String? {
        switch self {
        case .peerConnectionUnavailable:
            "Could not create a WebRTC peer connection."
        case .answerCreationFailed:
            "Could not create the WebRTC answer."
        case .iceConnectionFailed:
            "The WebRTC video connection failed."
        }
    }
}
