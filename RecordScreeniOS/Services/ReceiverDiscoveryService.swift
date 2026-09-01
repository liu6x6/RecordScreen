import Foundation
import Network
import UIKit

struct ReceiverPeer: Identifiable, Hashable {
    let endpoint: NWEndpoint
    let name: String

    var id: String { endpoint.debugDescription }
}

@MainActor
final class ReceiverDiscoveryService: ObservableObject {
    @Published private(set) var peers: [ReceiverPeer] = []
    @Published private(set) var state: StreamConnectionState = .idle
    @Published private(set) var connectedPeerName: String?
    @Published private(set) var errorMessage: String?

    private var browser: NWBrowser?
    private lazy var signalClient: TCPControlClient = {
        let client = TCPControlClient()
        client.onMessage = { [weak self] message in
            self?.handle(message)
        }
        client.onFailure = { [weak self] error in
            self?.report(error)
        }
        client.onDisconnected = { [weak self] in
            self?.handleDisconnect()
        }
        return client
    }()

    var onSignalMessage: ((SignalingMessage) -> Void)?
    var onControlDisconnected: (() -> Void)?

    func startBrowsing() {
        guard browser == nil else { return }

        AppLog.discovery.info("Starting Bonjour discovery for Mac receivers.")
        state = .preparing
        let browser = NWBrowser(
            for: .bonjour(type: LocalNetworkProtocol.bonjourType, domain: nil),
            using: .tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let peers = results.compactMap { result -> ReceiverPeer? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return ReceiverPeer(endpoint: result.endpoint, name: name)
            }
            Task { @MainActor in
                self?.peers = peers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                AppLog.discovery.info("Bonjour discovery found \(peers.count, privacy: .public) Mac receiver(s).")
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    AppLog.discovery.info("Bonjour discovery is ready.")
                    if self?.state == .preparing {
                        self?.state = .idle
                    }
                case let .failed(error):
                    self?.report(error)
                default:
                    break
                }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func connect(to peer: ReceiverPeer) {
        AppLog.signaling.info("Connecting to Mac receiver: \(peer.name, privacy: .public).")
        disconnect()
        state = .connecting
        errorMessage = nil
        signalClient.connect(to: peer.endpoint, deviceName: UIDevice.current.name)
    }

    func disconnect() {
        signalClient.disconnect()
        connectedPeerName = nil
        state = .idle
    }

    func send(_ message: SignalingMessage) throws {
        guard state == .connected else {
            throw SignalingError.handshakeIncomplete
        }
        try signalClient.send(message)
    }

    private func handle(_ message: SignalingMessage) {
        switch message.kind {
        case .ack:
            guard message.role == .receiver else {
                report(SignalingError.malformedMessage)
                return
            }
            connectedPeerName = message.deviceName ?? "Mac receiver"
            state = .connected
            AppLog.signaling.info("Received receiver acknowledgement from \(self.connectedPeerName ?? "unknown", privacy: .public).")
        case .disconnect:
            signalClient.disconnect()
            handleDisconnect()
        case .hello:
            report(SignalingError.malformedMessage)
        case .offer, .answer, .candidate:
            guard state == .connected else {
                report(SignalingError.handshakeIncomplete)
                return
            }
            onSignalMessage?(message)
        }
    }

    private func handleDisconnect() {
        let wasConnected = connectedPeerName != nil || state.isActive
        connectedPeerName = nil
        if case .failed = state {
        } else {
            state = .idle
        }
        if wasConnected {
            onControlDisconnected?()
        }
    }

    private func report(_ error: Error) {
        AppLog.signaling.error("iPhone signaling failed: \(error.localizedDescription, privacy: .public)")
        let wasConnected = connectedPeerName != nil || state.isActive
        signalClient.disconnect()
        connectedPeerName = nil
        errorMessage = error.localizedDescription
        state = .failed(error.localizedDescription)
        if wasConnected {
            onControlDisconnected?()
        }
    }
}
