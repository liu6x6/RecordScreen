import SwiftUI

struct CameraScreen: View {
    @StateObject private var camera = CameraCaptureService()
    @StateObject private var receiverDiscovery = ReceiverDiscoveryService()
    @StateObject private var publisher = WebRTCPublisher()
    @State private var configuration = StreamConfiguration()
    @State private var errorMessage: String?
    @State private var isShowingSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.Color.videoSurface
                .ignoresSafeArea()

            if let localVideoTrack = publisher.localVideoTrack {
                CameraPreview(videoTrack: localVideoTrack)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NativeCameraPreview(session: camera.captureSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            StreamControlOverlay(
                state: streamState,
                isStreaming: publisher.localVideoTrack != nil,
                isStartEnabled: canStartStreaming,
                onSettings: { isShowingSettings = true },
                onToggleStreaming: toggleStreaming
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            StreamSettingsScreen(
                receiverDiscovery: receiverDiscovery,
                configuration: $configuration,
                errorMessage: $errorMessage,
                onDismiss: { isShowingSettings = false }
            )
        }
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

    private var canStartStreaming: Bool {
        camera.isConfigured &&
            receiverDiscovery.state == .connected &&
            publisher.state != .preparing
    }

    private func toggleStreaming() {
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
