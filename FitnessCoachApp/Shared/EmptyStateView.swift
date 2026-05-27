import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.35))
                .accessibilityHidden(true)

            Text(title.uppercased())
                .font(FCFont.hero(28))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(AppConstants.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
