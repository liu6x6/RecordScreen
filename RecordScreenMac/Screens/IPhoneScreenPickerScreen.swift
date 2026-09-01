import SwiftUI

struct IPhoneScreenPickerScreen: View {
    @ObservedObject var screenCaptureService: IPhoneScreenCaptureService
    let onScreenSelected: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if screenCaptureService.devices.isEmpty {
                    ContentUnavailableView(
                        "No iPhone Screen Found",
                        systemImage: "rectangle.on.rectangle.slash",
                        description: Text("Connect and unlock an iPhone by USB, then wait a few seconds and refresh.")
                    )
                } else {
                    Section("Available iPhone Screens (\(screenCaptureService.devices.count))") {
                        ForEach(screenCaptureService.devices) { device in
                            HStack {
                                Label(device.name, systemImage: "iphone")
                                Spacer()
                                Button("Show Screen") {
                                    do {
                                        try screenCaptureService.start(using: device)
                                        onScreenSelected()
                                    } catch {
                                        return
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 480, minHeight: 320)
            .navigationTitle("iPhone Screens")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task {
                            await screenCaptureService.refreshDevices()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .task {
            await screenCaptureService.refreshDevices()
        }
    }
}
