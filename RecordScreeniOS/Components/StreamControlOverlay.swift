import SwiftUI

struct StreamControlOverlay: View {
    let state: StreamConnectionState
    let isStreaming: Bool
    let isStartEnabled: Bool
    let onSettings: () -> Void
    let onToggleStreaming: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            statusPill
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Stream settings")

            Button(isStreaming ? "Stop" : "Start", action: onToggleStreaming)
                .buttonStyle(.borderedProminent)
                .tint(isStreaming ? AppTheme.Color.error : AppTheme.Color.primary)
                .disabled(!isStreaming && !isStartEnabled)
        }
        .font(.headline)
        .foregroundStyle(AppTheme.Color.onVideoText)
        .padding(AppTheme.Spacing.small)
        .background(AppTheme.Color.overlaySurface, in: Capsule())
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.top, AppTheme.Spacing.small)
    }

    private var statusPill: some View {
        HStack(spacing: AppTheme.Spacing.xSmall) {
            Circle()
                .fill(state == .connected ? AppTheme.Color.live : AppTheme.Color.onVideoText.opacity(0.65))
                .frame(width: AppTheme.Spacing.small, height: AppTheme.Spacing.small)
            Text(state.title)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stream status: \(state.title)")
    }
}
