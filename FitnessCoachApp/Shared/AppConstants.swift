import SwiftUI

enum AppConstants {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Color {
        /// Brand yellow-green. Hex #B9EB00.
        static let brand = SwiftUI.Color(red: 185/255, green: 235/255, blue: 0/255)

        /// A darker shade for gradients and pressed states.
        static let brandDark = SwiftUI.Color(red: 140/255, green: 180/255, blue: 0/255)

        /// Foreground tone that sits well on the brand color (near-black —
        /// the brand yellow is very light/saturated so dark text reads best).
        static let onBrand = SwiftUI.Color(red: 30/255, green: 30/255, blue: 30/255)

        static let primary = brand

        /// Page background — explicit near-black (#0E0E0E) so the app is dark
        /// regardless of the system appearance setting.
        static let pageBackground = SwiftUI.Color(red: 0x0E/255, green: 0x0E/255, blue: 0x0E/255)

        /// Card surface — slightly lifted from the page background (#1A1A1A).
        static let cardBackground = SwiftUI.Color(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255)

        /// Soft yellow stroke used to outline cards on dark surfaces.
        static let cardStroke = brand.opacity(0.12)

        /// Two-stop gradient used in hero banners and user-message chat
        /// bubbles. Replaces the legacy blue→purple combo.
        static let brandGradient = LinearGradient(
            colors: [brand, brandDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Reusable background for top-level scroll containers: near-black base
    /// with a soft brand-yellow radial glow behind the top of the screen.
    struct BrandBackground: View {
        var body: some View {
            ZStack {
                Color.pageBackground
                RadialGradient(
                    colors: [Color.brand.opacity(0.18), .clear],
                    center: .init(x: 0.5, y: 0.0),
                    startRadius: 20,
                    endRadius: 380
                )
                .blendMode(.screen)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
    }

    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.75)
    }

    enum MinTapSize: CGFloat {
        case standard = 44
    }
}
