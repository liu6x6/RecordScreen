import SwiftUI

struct ReceiverScreen: View {
    @StateObject private var receiver = ReceiverService()

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

            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                    .fill(AppTheme.Color.videoSurface)
                if let remoteVideoTrack = receiver.remoteVideoTrack {
                    RemoteVideoView(videoTrack: remoteVideoTrack)
                } else {
                    ContentUnavailableView(
                        "No Live Video",
                        systemImage: "video.slash",
                        description: Text("Start the receiver, then connect from the iPhone app.")
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
        .alert("Receiver Error", isPresented: Binding(
            get: { receiver.errorMessage != nil },
            set: { if !$0 { receiver.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(receiver.errorMessage ?? "")
        }
    }
}
