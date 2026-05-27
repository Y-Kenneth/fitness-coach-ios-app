import SwiftUI

// MARK: - Generic stat card (white surface, Bebas number)

struct StatCardView: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    /// Kept on the signature for backwards compatibility with old call sites;
    /// the v2 visual treats every stat card's icon as teal accent.
    let tint: Color

    init(title: String, value: String, unit: String, systemImage: String, tint: Color = AppConstants.Color.accent) {
        self.title = title
        self.value = value
        self.unit = unit
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        FCCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.accent)
                    .accessibilityHidden(true)

                Text(value)
                    .font(FCFont.stat(40))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                FCSectionLabel(text: title)

                Text(unit)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}
