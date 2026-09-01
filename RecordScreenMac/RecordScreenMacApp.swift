import SwiftUI

@main
struct RecordScreenMacApp: App {
    @StateObject private var screenCapture = IPhoneScreenCaptureService()

    var body: some Scene {
        WindowGroup {
            ReceiverScreen(screenCapture: screenCapture)
                .frame(minWidth: 760, minHeight: 520)
        }

        WindowGroup("iPhone Screen", id: "iphone-screen") {
            IPhoneScreenWindow()
                .environmentObject(screenCapture)
                .frame(minWidth: 320, minHeight: 240)
        }
    }
}
