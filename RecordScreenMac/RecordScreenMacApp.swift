import SwiftUI

@main
struct RecordScreenMacApp: App {
    @StateObject private var receiver: ReceiverService
    @StateObject private var continuityCamera: ContinuityCameraService
    @StateObject private var screenCapture: IPhoneScreenCaptureService
    @StateObject private var recordingCoordinator: RecordingCoordinator

    init() {
        let receiver = ReceiverService()
        let continuityCamera = ContinuityCameraService()
        let screenCapture = IPhoneScreenCaptureService()

        _receiver = StateObject(wrappedValue: receiver)
        _continuityCamera = StateObject(wrappedValue: continuityCamera)
        _screenCapture = StateObject(wrappedValue: screenCapture)
        _recordingCoordinator = StateObject(
            wrappedValue: RecordingCoordinator(
                receiver: receiver,
                continuityCamera: continuityCamera,
                screenCapture: screenCapture
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ReceiverScreen(
                receiver: receiver,
                continuityCamera: continuityCamera,
                screenCapture: screenCapture,
                recordingCoordinator: recordingCoordinator
            )
                .frame(minWidth: 760, minHeight: 520)
        }

        WindowGroup("iPhone Screen", id: "iphone-screen") {
            IPhoneScreenWindow()
                .environmentObject(screenCapture)
                .environmentObject(recordingCoordinator)
                .frame(minWidth: 320, minHeight: 240)
        }
    }
}
