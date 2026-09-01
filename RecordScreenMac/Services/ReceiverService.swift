import Foundation
@preconcurrency import WebRTC

@MainActor
final class ReceiverService: ObservableObject, StreamReceiver {
    @Published private(set) var state: StreamConnectionState = .idle
    @Published private(set) var connectedPeerName: String?
    @Published private(set) var remoteVideoTrack: RTCVideoTrack?
    @Published private(set) var errorMessage: String?

    var onRemoteVideoTrackChanged: ((RTCVideoTrack?) -> Void)?

    private var server: LocalReceiverServer?
    private let webRTCReceiver = WebRTCReceiver()

    init() {
        webRTCReceiver.onLocalCandidate = { [weak self] message in
            do {
                try self?.server?.send(message)
            } catch {
                self?.report(error)
            }
        }
        webRTCReceiver.onConnectionStateChanged = { [weak self] state in
            self?.state = state
        }
        webRTCReceiver.onRemoteVideoTrackChanged = { [weak self] track in
            self?.remoteVideoTrack = track
            self?.onRemoteVideoTrackChanged?(track)
        }
        webRTCReceiver.onError = { [weak self] error in
            self?.handleConnectionFailure(error)
        }
    }

    func startReceiving() async throws {
        if server != nil {
            stopReceiving()
        }
        state = .preparing
        errorMessage = nil
        do {
            try webRTCReceiver.prepare()
        } catch {
            report(error)
            throw error
        }
        let server = LocalReceiverServer(
            onPeerConnected: { [weak self] deviceName in
                AppLog.signaling.info("Receiver service registered connected iPhone: \(deviceName, privacy: .public).")
                self?.connectedPeerName = deviceName
                self?.state = .connected
            },
            onSignalMessage: { [weak self] message in
                Task { @MainActor in
                    guard let self else { return }
                    do {
                        try await self.webRTCReceiver.handle(message)
                    } catch {
                        self.handleConnectionFailure(error)
                    }
                }
            },
            onPeerDisconnected: { [weak self] in
                self?.webRTCReceiver.stop()
                self?.remoteVideoTrack = nil
                self?.connectedPeerName = nil
                if self?.server != nil {
                    self?.state = .connecting
                }
            },
            onFailure: { [weak self] error in
                self?.handleConnectionFailure(error)
            }
        )
        do {
            try server.start()
            self.server = server
            state = .connecting
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stopReceiving() {
        connectedPeerName = nil
        remoteVideoTrack = nil
        server?.stop()
        server = nil
        webRTCReceiver.stop()
        state = .idle
    }

    func report(_ error: Error) {
        AppLog.signaling.error("Receiver service error: \(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription
        state = .failed(error.localizedDescription)
    }

    func dismissError() {
        errorMessage = nil
    }

    var isReceiving: Bool {
        server != nil
    }

    private func handleConnectionFailure(_ error: Error) {
        webRTCReceiver.stop()
        remoteVideoTrack = nil
        connectedPeerName = nil
        report(error)
    }
}
