import SwiftUI

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.Color.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                    .strokeBorder(.quaternary)
            }
    }
}

extension View {
    func appCard() -> some View {
        modifier(CardStyle())
    }
}
