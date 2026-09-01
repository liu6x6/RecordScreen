import Foundation
import Network

@MainActor
final class LocalReceiverServer: SignalingTransport {
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var receiveBuffer = Data()
    private var hasCompletedHandshake = false

    private let onPeerConnected: (String) -> Void
    private let onSignalMessage: (SignalingMessage) -> Void
    private let onPeerDisconnected: () -> Void
    private let onFailure: (Error) -> Void

    init(
        onPeerConnected: @escaping (String) -> Void,
        onSignalMessage: @escaping (SignalingMessage) -> Void,
        onPeerDisconnected: @escaping () -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.onPeerConnected = onPeerConnected
        self.onSignalMessage = onSignalMessage
        self.onPeerDisconnected = onPeerDisconnected
        self.onFailure = onFailure
    }

    func start() throws {
        guard listener == nil else { return }

        AppLog.signaling.info("Starting Mac Bonjour receiver service.")
        let listener = try NWListener(using: .tcp, on: .any)
        listener.service = NWListener.Service(
            name: Host.current().localizedName ?? "RecordScreen Mac",
            type: LocalNetworkProtocol.bonjourType
        )
        listener.stateUpdateHandler = { [weak self] state in
            guard case let .failed(error) = state else { return }
            Task { @MainActor in
                self?.onFailure(error)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                AppLog.signaling.info("Mac accepted a new TCP signaling connection.")
                self?.accept(connection)
            }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    func stop() {
        closeActiveConnection(notify: false)
        listener?.cancel()
        listener = nil
    }

    func send(_ message: SignalingMessage) throws {
        guard let activeConnection else {
            throw SignalingError.unavailable
        }

        var data = try JSONEncoder().encode(message)
        AppLog.signaling.info("Mac sending signaling message: \(message.kind.rawValue, privacy: .public).")
        data.append(0x0A)
        activeConnection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.fail(error)
            }
        })
    }

    func disconnect() {
        closeActiveConnection(notify: true)
    }

    private func accept(_ connection: NWConnection) {
        guard activeConnection == nil else {
            AppLog.signaling.notice("Rejected an additional TCP signaling connection while an iPhone is connected.")
            connection.cancel()
            return
        }

        activeConnection = connection
        receiveBuffer.removeAll(keepingCapacity: false)
        hasCompletedHandshake = false

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            Task { @MainActor in
                self?.handleConnectionState(state, for: connection)
            }
        }
        connection.start(queue: .main)
    }

    private func handleConnectionState(_ state: NWConnection.State, for connection: NWConnection) {
        guard activeConnection === connection else { return }

        switch state {
        case .ready:
            AppLog.signaling.info("Mac TCP signaling connection is ready.")
            receiveNext(from: connection)
        case let .failed(error):
            fail(error)
        case .cancelled:
            closeActiveConnection(notify: true, cancelConnection: false)
        default:
            break
        }
    }

    private func receiveNext(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let connection else { return }
            Task { @MainActor in
                guard let self, self.activeConnection === connection else { return }

                if let error {
                    self.fail(error)
                    return
                }
                if let data {
                    self.receiveBuffer.append(data)
                    self.decodeAvailableMessages()
                }
                if isComplete {
                    self.closeActiveConnection(notify: true, cancelConnection: false)
                    return
                }
                self.receiveNext(from: connection)
            }
        }
    }

    private func decodeAvailableMessages() {
        let delimiter = Data([0x0A])
        while let range = receiveBuffer.range(of: delimiter) {
            let messageData = receiveBuffer.subdata(in: 0..<range.lowerBound)
            receiveBuffer.removeSubrange(0..<range.upperBound)
            guard !messageData.isEmpty else { continue }

            do {
                let message = try JSONDecoder().decode(SignalingMessage.self, from: messageData)
                AppLog.signaling.info("Mac received signaling message: \(message.kind.rawValue, privacy: .public).")
                try handle(message)
            } catch {
                fail(LocalReceiverServerError.invalidMessage)
                return
            }
        }
    }

    private func handle(_ message: SignalingMessage) throws {
        if !hasCompletedHandshake {
            guard message.kind == .hello,
                  message.role == .publisher,
                  let deviceName = message.deviceName else {
                throw LocalReceiverServerError.invalidHandshake
            }
            hasCompletedHandshake = true
            try send(.acknowledgement(deviceName: Host.current().localizedName ?? "RecordScreen Mac"))
            AppLog.signaling.info("Mac completed handshake with iPhone: \(deviceName, privacy: .public).")
            onPeerConnected(deviceName)
            return
        }

        if message.kind == .disconnect {
            closeActiveConnection(notify: true)
            return
        }
        guard message.kind != .hello, message.kind != .ack else {
            throw LocalReceiverServerError.invalidMessage
        }
        onSignalMessage(message)
    }

    private func fail(_ error: Error) {
        AppLog.signaling.error("Mac signaling failure: \(error.localizedDescription, privacy: .public)")
        closeActiveConnection(notify: false)
        onFailure(error)
    }

    private func closeActiveConnection(notify: Bool, cancelConnection: Bool = true) {
        let connection = activeConnection
        let shouldNotify = notify && (hasCompletedHandshake || connection != nil)
        activeConnection = nil
        receiveBuffer.removeAll(keepingCapacity: false)
        hasCompletedHandshake = false
        if cancelConnection {
            connection?.cancel()
        }
        if shouldNotify {
            onPeerDisconnected()
        }
    }
}

private enum LocalReceiverServerError: LocalizedError {
    case invalidHandshake
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .invalidHandshake:
            "A device sent an invalid connection handshake."
        case .invalidMessage:
            "A device sent an invalid signaling message."
        }
    }
}
