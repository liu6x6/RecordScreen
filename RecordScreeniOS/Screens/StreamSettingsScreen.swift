import SwiftUI

struct StreamSettingsScreen: View {
    @ObservedObject var receiverDiscovery: ReceiverDiscoveryService
    @Binding var configuration: StreamConfiguration
    @Binding var errorMessage: String?
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Mac Receiver") {
                    if receiverDiscovery.peers.isEmpty {
                        ContentUnavailableView(
                            "No Mac Receiver Found",
                            systemImage: "macbook.and.iphone",
                            description: Text("Start Receiver on the Mac and keep both devices on the same Wi-Fi network.")
                        )
                    } else {
                        ForEach(receiverDiscovery.peers) { peer in
                            HStack {
                                Label(peer.name, systemImage: "desktopcomputer")
                                Spacer()
                                Button(receiverDiscovery.connectedPeerName == peer.name ? "Connected" : "Connect") {
                                    receiverDiscovery.connect(to: peer)
                                }
                                .disabled(receiverDiscovery.connectedPeerName == peer.name)
                            }
                        }
                    }
                }

                Section("Video Quality") {
                    Picker("Resolution", selection: $configuration.resolution) {
                        ForEach(StreamConfiguration.Resolution.allCases) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Stream Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .onChange(of: receiverDiscovery.errorMessage) { _, message in
            if let message {
                errorMessage = message
            }
        }
    }
}
