import SwiftUI

struct IPhoneScreenWindow: View {
    @EnvironmentObject private var screenCapture: IPhoneScreenCaptureService
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Rotate 90 Degrees", systemImage: "rotate.right") {
                    rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
                }
                .accessibilityLabel("Rotate iPhone screen 90 degrees clockwise")
            }
        }
        .animation(AppTheme.Animation.feedback, value: rotationQuarterTurns)
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
