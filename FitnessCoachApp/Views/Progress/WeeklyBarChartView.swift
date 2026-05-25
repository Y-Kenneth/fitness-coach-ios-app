import SwiftUI

struct WeeklyBarChartView: View {
    let data: [(String, Int)]

    private var maxValue: Int {
        data.map(\.1).max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppConstants.Spacing.sm) {
            ForEach(data, id: \.0) { label, value in
                BarColumnView(
                    label: label,
                    value: value,
                    maxValue: maxValue
                )
            }
        }
        .padding(AppConstants.Spacing.md)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly activity chart")
        .accessibilityValue(data.map { "\($0.0): \($0.1) sessions" }.joined(separator: ", "))
    }
}

private struct BarColumnView: View {
    let label: String
    let value: Int
    let maxValue: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animatedHeight: CGFloat = 0

    private var targetHeight: CGFloat {
        guard maxValue > 0 else { return 4 }
        return max(4, CGFloat(value) / CGFloat(maxValue) * 120)
    }

    var body: some View {
        VStack(spacing: AppConstants.Spacing.xs) {
            if value > 0 {
                Text("\(value)")
                    .font(.caption2.bold())
                    .foregroundStyle(AppConstants.Color.brandDark)
            } else {
                Text(" ")
                    .font(.caption2)
            }

            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.sm)
                .fill(value > 0 ? AppConstants.Color.brand : Color.secondary.opacity(0.2))
                .frame(height: animatedHeight)
                .frame(maxWidth: .infinity)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if reduceMotion {
                animatedHeight = targetHeight
            } else {
                withAnimation(AppConstants.Animation.spring.delay(0.1)) {
                    animatedHeight = targetHeight
                }
            }
        }
        .onChange(of: value) { _ in
            withAnimation(reduceMotion ? .none : AppConstants.Animation.spring) {
                animatedHeight = targetHeight
            }
        }
    }
}
