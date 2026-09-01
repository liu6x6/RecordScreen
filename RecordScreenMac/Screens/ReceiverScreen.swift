import SwiftUI

struct ReceiverScreen: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var receiver: ReceiverService
    @ObservedObject var continuityCamera: ContinuityCameraService
    @ObservedObject var screenCapture: IPhoneScreenCaptureService
    @ObservedObject var recordingCoordinator: RecordingCoordinator
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
                recordingButton
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
            .onChange(of: previewSource) { previous, source in
                Task {
                    await recordingCoordinator.stopRecording(ifActiveSource: previous.recordingSource)
                }
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
                Text(recordingCoordinator.recordingService.state.statusText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Color.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
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
            Task {
                await recordingCoordinator.stopRecording()
            }
            continuityCamera.stop()
        }
    }

    @ViewBuilder
    private var recordingButton: some View {
        if recordingCoordinator.isRecording(from: previewSource.recordingSource) {
            Button("Stop Recording", systemImage: "stop.fill") {
                Task {
                    await recordingCoordinator.stopRecording()
                }
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button("Record", systemImage: "record.circle") {
                Task {
                    await recordingCoordinator.startRecording(from: previewSource.recordingSource)
                }
            }
            .buttonStyle(.bordered)
            .disabled(recordingCoordinator.recordingService.state.isBusy)
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

    var recordingSource: RecordingSource {
        switch self {
        case .webRTC:
            .webRTC
        case .continuityCamera:
            .continuityCamera
        }
    }
}
