import SwiftUI

struct ReceiverStatusCard: View {
    let state: StreamConnectionState

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Circle()
                .fill(state == .connected ? AppTheme.Color.live : AppTheme.Color.secondaryText)
                .frame(width: AppTheme.Spacing.small, height: AppTheme.Spacing.small)
            Text(state.title)
                .font(.headline)
            Spacer()
            Text(state == .connected ? "Receiving live video" : "Waiting for iPhone")
                .font(.caption)
                .foregroundStyle(AppTheme.Color.secondaryText)
        }
        .appCard()
        .animation(AppTheme.Animation.feedback, value: state)
    }
}
