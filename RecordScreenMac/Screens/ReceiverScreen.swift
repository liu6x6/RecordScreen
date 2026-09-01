import SwiftUI

struct ReceiverScreen: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var receiver = ReceiverService()
    @StateObject private var continuityCamera = ContinuityCameraService()
    @ObservedObject var screenCapture: IPhoneScreenCaptureService
    @State private var previewSource: PreviewSource = .webRTC
    @State private var isShowingCameraPicker = false
    @State private var isShowingScreenPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    Text("Receiver")
                        .font(.title.bold())
                    Text(receiver.connectedPeerName.map { "Connected to \($0)." } ?? "Discoverable to iPhones on this Wi-Fi network.")
                        .foregroundStyle(AppTheme.Color.secondaryText)
                }
                Spacer()
                Button("Find iPhone Camera", systemImage: "iphone.and.arrow.forward") {
                    isShowingCameraPicker = true
                }
                Button("Find iPhone Screen", systemImage: "rectangle.on.rectangle") {
                    isShowingScreenPicker = true
                }
                Button("Start Receiver") {
                    Task {
                        do {
                            try await receiver.startReceiving()
                        } catch {
                            receiver.report(error)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(receiver.state.isActive)
            }

            Picker("Preview Source", selection: $previewSource) {
                ForEach(PreviewSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: previewSource) { _, source in
                switch source {
                case .webRTC:
                    continuityCamera.stop()
                    screenCapture.stop()
                case .continuityCamera:
                    screenCapture.stop()
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                    .fill(AppTheme.Color.videoSurface)
                if previewSource == .continuityCamera, continuityCamera.isCapturing {
                    ContinuityCameraPreview(session: continuityCamera.captureSession)
                } else if previewSource == .webRTC, let remoteVideoTrack = receiver.remoteVideoTrack {
                    RemoteVideoView(videoTrack: remoteVideoTrack)
                } else {
                    ContentUnavailableView(
                        previewSource.emptyStateTitle,
                        systemImage: previewSource.emptyStateIcon,
                        description: Text(previewSource.emptyStateDescription
                        )
                    )
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ReceiverStatusCard(state: receiver.state)

            HStack {
                Button("Stop Receiver", role: .cancel) {
                    receiver.stopReceiving()
                }
                .disabled(!receiver.isReceiving)
                Spacer()
                Text("LAN video preview only — recording is not available yet.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Color.secondaryText)
            }
        }
        .padding(AppTheme.Spacing.large)
        .sheet(isPresented: $isShowingCameraPicker) {
            ContinuityCameraPickerScreen(
                cameraService: continuityCamera,
                onCameraSelected: {
                    previewSource = .continuityCamera
                    isShowingCameraPicker = false
                },
                onDismiss: { isShowingCameraPicker = false }
            )
        }
        .sheet(isPresented: $isShowingScreenPicker) {
            IPhoneScreenPickerScreen(
                screenCaptureService: screenCapture,
                onScreenSelected: {
                    isShowingScreenPicker = false
                    openWindow(id: "iphone-screen")
                },
                onDismiss: { isShowingScreenPicker = false }
            )
        }
        .alert("Receiver Error", isPresented: Binding(
            get: { receiver.errorMessage != nil },
            set: { if !$0 { receiver.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(receiver.errorMessage ?? "")
        }
        .alert("iPhone Camera Error", isPresented: Binding(
            get: { continuityCamera.errorMessage != nil },
            set: { if !$0 { continuityCamera.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(continuityCamera.errorMessage ?? "")
        }
        .alert("iPhone Screen Error", isPresented: Binding(
            get: { screenCapture.errorMessage != nil },
            set: { if !$0 { screenCapture.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(screenCapture.errorMessage ?? "")
        }
        .onDisappear {
            continuityCamera.stop()
        }
    }
}

private enum PreviewSource: String, CaseIterable, Identifiable {
    case webRTC
    case continuityCamera

    var id: Self { self }

    var title: String {
        switch self {
        case .webRTC: "WebRTC Stream"
        case .continuityCamera: "iPhone Camera"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .webRTC: "No WebRTC Video"
        case .continuityCamera: "No iPhone Camera Selected"
        }
    }

    var emptyStateIcon: String {
        switch self {
        case .webRTC: "video.slash"
        case .continuityCamera: "iphone.slash"
        }
    }

    var emptyStateDescription: String {
        switch self {
        case .webRTC: "Start the receiver, then connect from the iPhone app."
        case .continuityCamera: "Find and select an iPhone camera connected to this Mac."
        }
    }
}
