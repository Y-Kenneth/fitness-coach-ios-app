import SwiftUI

struct StatCardView: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Spacer()
            }

            Text(value)
                .font(.title.bold())
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(unit)
                .font(.caption2)
                .foregroundStyle(tint)
        }
        .padding(AppConstants.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                .stroke(AppConstants.Color.cardStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}
