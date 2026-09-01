import SwiftUI

struct CameraScreen: View {
    @StateObject private var camera = CameraCaptureService()
    @StateObject private var receiverDiscovery = ReceiverDiscoveryService()
    @StateObject private var publisher = WebRTCPublisher()
    @State private var configuration = StreamConfiguration()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
                ZStack {
                    if let localVideoTrack = publisher.localVideoTrack {
                        CameraPreview(videoTrack: localVideoTrack)
                    } else {
                        NativeCameraPreview(session: camera.captureSession)
                    }
                }
                .background(AppTheme.Color.videoSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                .overlay(alignment: .topLeading) {
                    Text("iPhone Camera")
                        .font(.caption.weight(.semibold))
                        .padding(AppTheme.Spacing.small)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(AppTheme.Spacing.medium)
                }

                StreamStatusCard(state: streamState)

            if receiverDiscovery.peers.isEmpty {
                ContentUnavailableView(
                    "No Mac Receiver Found",
                    systemImage: "macbook.and.iphone",
                    description: Text("Start Receiver on the Mac, then keep both devices on the same Wi-Fi network.")
                )
                .frame(maxWidth: .infinity)
                .appCard()
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(receiverDiscovery.peers) { peer in
                        HStack {
                            Label(peer.name, systemImage: "desktopcomputer")
                            Spacer()
                            Button(receiverDiscovery.connectedPeerName == peer.name ? "Connected" : "Connect") {
                                receiverDiscovery.connect(to: peer)
                            }
                            .disabled(receiverDiscovery.connectedPeerName == peer.name)
                        }
                        .appCard()
                    }
                }
            }

            Picker("Quality", selection: $configuration.resolution) {
                ForEach(StreamConfiguration.Resolution.allCases) { resolution in
                    Text(resolution.rawValue).tag(resolution)
                }
            }
            .pickerStyle(.segmented)

            Button(publisher.localVideoTrack == nil ? "Start Streaming" : "Stop Streaming") {
                if publisher.localVideoTrack == nil {
                    Task {
                        do {
                            camera.stopPreview()
                            try await publisher.startPublishing(configuration: configuration)
                        } catch {
                            camera.startPreview()
                            errorMessage = error.localizedDescription
                        }
                    }
                } else {
                    publisher.stopPublishing()
                    camera.startPreview()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(
                !camera.isConfigured ||
                    receiverDiscovery.state != .connected ||
                    publisher.state == .preparing
            )
        }
        .padding(AppTheme.Spacing.medium)
        .onAppear {
            configureSignaling()
        }
        .task {
            do {
                try await camera.requestAccessAndConfigure()
                camera.startPreview()
                receiverDiscovery.startBrowsing()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Camera Unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: receiverDiscovery.errorMessage) { _, message in
            if let message {
                errorMessage = message
            }
        }
        .onDisappear {
            publisher.stopPublishing()
            receiverDiscovery.disconnect()
            camera.stopPreview()
        }
    }

    private var streamState: StreamConnectionState {
        publisher.state == .idle ? receiverDiscovery.state : publisher.state
    }

    private func configureSignaling() {
        publisher.signalSender = { message in
            try receiverDiscovery.send(message)
        }
        publisher.onError = { error in
            errorMessage = error.localizedDescription
        }
        receiverDiscovery.onSignalMessage = { message in
            Task {
                do {
                    try await publisher.handle(message)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        receiverDiscovery.onControlDisconnected = {
            publisher.stopPublishing()
        }
    }
}
