import SwiftUI

struct ContinuityCameraPickerScreen: View {
    @ObservedObject var cameraService: ContinuityCameraService
    let onCameraSelected: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if cameraService.devices.isEmpty {
                    ContentUnavailableView(
                        "No iPhone Camera Found",
                        systemImage: "iphone.slash",
                        description: Text("Connect an iPhone by USB, unlock it, and ensure Continuity Camera is enabled, then refresh.")
                    )
                } else {
                    Section("Available iPhone Cameras (\(cameraService.devices.count))") {
                        ForEach(cameraService.devices) { device in
                            HStack {
                                Label(device.name, systemImage: "iphone")
                                Spacer()
                                Button("Use Camera") {
                                    do {
                                        try cameraService.start(using: device)
                                        onCameraSelected()
                                    } catch {
                                        AppLog.camera.error(
                                            "Could not start selected Continuity Camera: \(error.localizedDescription, privacy: .public)"
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 480, minHeight: 320)
            .navigationTitle("iPhone Cameras")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task {
                            await cameraService.refreshDevices()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .task {
            await cameraService.refreshDevices()
        }
    }
}
