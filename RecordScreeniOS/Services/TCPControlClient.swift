import Foundation
import Network

@MainActor
final class TCPControlClient: SignalingTransport {
    var onMessage: ((SignalingMessage) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onDisconnected: (() -> Void)?

    private var connection: NWConnection?
    private var receiveBuffer = Data()

    func connect(to endpoint: NWEndpoint, deviceName: String) {
        disconnect()
        AppLog.signaling.info("Opening TCP signaling connection as \(deviceName, privacy: .public).")

        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            Task { @MainActor in
                self?.handleConnectionState(state, for: connection, deviceName: deviceName)
            }
        }
        self.connection = connection
        connection.start(queue: .main)
    }

    func send(_ message: SignalingMessage) throws {
        guard let connection else {
            throw SignalingError.unavailable
        }

        var data = try JSONEncoder().encode(message)
        AppLog.signaling.info("iPhone sending signaling message: \(message.kind.rawValue, privacy: .public).")
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.fail(error)
            }
        })
    }

    func disconnect() {
        let connection = connection
        self.connection = nil
        receiveBuffer.removeAll(keepingCapacity: false)
        connection?.cancel()
    }

    private func handleConnectionState(
        _ state: NWConnection.State,
        for connection: NWConnection,
        deviceName: String
    ) {
        guard self.connection === connection else { return }

        switch state {
        case .ready:
            AppLog.signaling.info("iPhone TCP signaling connection is ready; sending handshake.")
            receiveNext(from: connection)
            do {
                try send(.hello(deviceName: deviceName, role: .publisher))
            } catch {
                fail(error)
            }
        case let .failed(error):
            fail(error)
        case .cancelled:
            self.connection = nil
            receiveBuffer.removeAll(keepingCapacity: false)
            onDisconnected?()
        default:
            break
        }
    }

    private func receiveNext(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let connection else { return }
            Task { @MainActor in
                guard let self, self.connection === connection else { return }

                if let error {
                    self.fail(error)
                    return
                }
                if let data {
                    self.receiveBuffer.append(data)
                    self.decodeAvailableMessages()
                }
                if isComplete {
                    self.connection = nil
                    self.receiveBuffer.removeAll(keepingCapacity: false)
                    self.onDisconnected?()
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
                AppLog.signaling.info("iPhone received signaling message: \(message.kind.rawValue, privacy: .public).")
                onMessage?(message)
            } catch {
                fail(SignalingError.malformedMessage)
                return
            }
        }
    }

    private func fail(_ error: Error) {
        AppLog.signaling.error("iPhone TCP signaling failure: \(error.localizedDescription, privacy: .public)")
        let connection = connection
        self.connection = nil
        receiveBuffer.removeAll(keepingCapacity: false)
        connection?.cancel()
        onFailure?(error)
    }
}
