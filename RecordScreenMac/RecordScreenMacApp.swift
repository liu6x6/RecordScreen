import SwiftUI

@main
struct RecordScreenMacApp: App {
    var body: some Scene {
        WindowGroup {
            ReceiverScreen()
                .frame(minWidth: 760, minHeight: 520)
        }
    }
}
