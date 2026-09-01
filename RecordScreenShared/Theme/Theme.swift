import SwiftUI

enum AppTheme {
    enum Color {
        static let primary = SwiftUI.Color.accentColor
        static let surface = SwiftUI.Color.primary.opacity(0.04)
        static let text = SwiftUI.Color.primary
        static let secondaryText = SwiftUI.Color.secondary
        static let error = SwiftUI.Color.red
        static let live = SwiftUI.Color.red
        static let videoSurface = SwiftUI.Color.black
        static let overlaySurface = SwiftUI.Color.black.opacity(0.48)
        static let onVideoText = SwiftUI.Color.white
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 12
        static let control: CGFloat = 8
    }

    enum Animation {
        static let feedback = SwiftUI.Animation.easeInOut(duration: 0.2)
    }
}
