import SwiftUI

struct WeeklyBarChartView: View {
    let data: [(String, Int)]
    /// When true, the last bar is the "current" one (used by the monthly view
    /// where the rightmost bar represents this week).
    var highlightLast: Bool = false

    private var maxValue: Int { max(1, data.map(\.1).max() ?? 1) }

    /// Index of "today" inside the data array (Mon=0..Sun=6).
    private var todayIndex: Int {
        if highlightLast { return data.count - 1 }
        let weekday = Calendar.current.component(.weekday, from: Date())
        // weekday: 1=Sun .. 7=Sat. Map to Mon-first index.
        return weekday == 1 ? 6 : weekday - 2
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(Array(data.enumerated()), id: \.offset) { idx, item in
                BarColumnView(
                    label: item.0,
                    value: item.1,
                    maxValue: maxValue,
                    isToday: idx == todayIndex
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(highlightLast ? "Monthly activity chart" : "Weekly activity chart")
        .accessibilityValue(data.map { "\($0.0): \($0.1) sessions" }.joined(separator: ", "))
    }
}

private struct BarColumnView: View {
    let label: String
    let value: Int
    let maxValue: Int
    let isToday: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedHeight: CGFloat = 0

    private var targetHeight: CGFloat {
        guard maxValue > 0, value > 0 else { return 6 }
        return max(6, CGFloat(value) / CGFloat(maxValue) * 130)
    }

    var body: some View {
        VStack(spacing: 8) {
            if value > 0 {
                Text("\(value)")
                    .font(FCFont.stat(16))
                    .foregroundStyle(AppConstants.Color.textOnCard)
            } else {
                Text(" ")
                    .font(.caption2)
            }

            Group {
                if isToday && value > 0 {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppConstants.Color.accent)
                        .shadow(color: AppConstants.Color.accent.opacity(0.55), radius: 10)
                        .shadow(color: AppConstants.Color.accent.opacity(0.40), radius: 3)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(value > 0
                              ? AppConstants.Color.cardSecondary.opacity(0.9)
                              : AppConstants.Color.divider.opacity(0.6))
                }
            }
            .frame(height: animatedHeight)
            .frame(maxWidth: .infinity)

            Text(label.uppercased())
                .font(FCFont.label(10))
                .tracking(0.8)
                .foregroundStyle(AppConstants.Color.mutedOnCard)
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
