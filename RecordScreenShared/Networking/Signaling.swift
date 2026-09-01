import Foundation

struct SignalingMessage: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case hello
        case ack
        case offer
        case answer
        case candidate
        case disconnect
    }

    let kind: Kind
    let deviceName: String?
    let role: PeerHandshake.Role?
    let sdp: String?
    let candidate: ICECandidateMessage?

    init(
        kind: Kind,
        deviceName: String? = nil,
        role: PeerHandshake.Role? = nil,
        sdp: String? = nil,
        candidate: ICECandidateMessage? = nil
    ) {
        self.kind = kind
        self.deviceName = deviceName
        self.role = role
        self.sdp = sdp
        self.candidate = candidate
    }

    static func hello(deviceName: String, role: PeerHandshake.Role) -> Self {
        Self(kind: .hello, deviceName: deviceName, role: role)
    }

    static func acknowledgement(deviceName: String) -> Self {
        Self(kind: .ack, deviceName: deviceName, role: .receiver)
    }

    static func offer(sdp: String) -> Self {
        Self(kind: .offer, sdp: sdp)
    }

    static func answer(sdp: String) -> Self {
        Self(kind: .answer, sdp: sdp)
    }

    static func candidate(_ candidate: ICECandidateMessage) -> Self {
        Self(kind: .candidate, candidate: candidate)
    }
}

struct ICECandidateMessage: Codable, Sendable {
    let sdp: String
    let sdpMid: String?
    let sdpMLineIndex: Int32
}

@MainActor
protocol SignalingTransport: AnyObject {
    func send(_ message: SignalingMessage) throws
    func disconnect()
}

enum SignalingError: LocalizedError {
    case unavailable
    case handshakeIncomplete
    case malformedMessage

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The TCP signaling connection is unavailable."
        case .handshakeIncomplete:
            "The receiver handshake has not completed."
        case .malformedMessage:
            "The receiver sent an invalid signaling message."
        }
    }
}
