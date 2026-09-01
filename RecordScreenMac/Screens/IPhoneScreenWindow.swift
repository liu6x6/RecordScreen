import SwiftUI

struct IPhoneScreenWindow: View {
    @EnvironmentObject private var screenCapture: IPhoneScreenCaptureService
    @EnvironmentObject private var recordingCoordinator: RecordingCoordinator
    @State private var rotationQuarterTurns = 0

    var body: some View {
        ZStack {
            AppTheme.Color.videoSurface

            if screenCapture.isCapturing {
                GeometryReader { proxy in
                    ContinuityCameraPreview(session: screenCapture.captureSession)
                        .frame(
                            width: isSideways ? proxy.size.height : proxy.size.width,
                            height: isSideways ? proxy.size.width : proxy.size.height
                        )
                        .rotationEffect(.degrees(Double(rotationQuarterTurns * 90)))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            } else {
                ContentUnavailableView(
                    "iPhone Screen Unavailable",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("Choose an iPhone screen from the main receiver window.")
                )
                .foregroundStyle(AppTheme.Color.onVideoText)
            }

            AspectRatioWindowConfigurator(contentSize: displayedVideoSize)
                .frame(width: 0, height: 0)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(recordingCoordinator.recordingService.state.statusText)
                .font(.caption)
                .foregroundStyle(AppTheme.Color.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.xSmall)
                .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                recordingButton
                Button("Rotate 90 Degrees", systemImage: "rotate.right") {
                    rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
                }
                .accessibilityLabel("Rotate iPhone screen 90 degrees clockwise")
            }
        }
        .animation(AppTheme.Animation.feedback, value: rotationQuarterTurns)
        .onDisappear {
            Task {
                await recordingCoordinator.stopRecording(ifActiveSource: .iPhoneScreen)
            }
        }
    }

    @ViewBuilder
    private var recordingButton: some View {
        if recordingCoordinator.isRecording(from: .iPhoneScreen) {
            Button("Stop Recording", systemImage: "stop.fill") {
                Task {
                    await recordingCoordinator.stopRecording(ifActiveSource: .iPhoneScreen)
                }
            }
        } else {
            Button("Record", systemImage: "record.circle") {
                Task {
                    await recordingCoordinator.startRecording(from: .iPhoneScreen)
                }
            }
            .disabled(!screenCapture.isCapturing || recordingCoordinator.recordingService.state.isBusy)
        }
    }

    private var isSideways: Bool {
        rotationQuarterTurns % 2 != 0
    }

    private var displayedVideoSize: CGSize {
        let size = screenCapture.videoSize
        guard isSideways else { return size }
        return CGSize(width: size.height, height: size.width)
    }
}
