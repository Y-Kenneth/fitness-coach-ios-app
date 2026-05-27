import SwiftUI

struct FitnessProgressView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @State private var range: ProgressRange = .week

    enum ProgressRange: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month"
        var id: String { rawValue }
    }

    private var sessionsInRange: [WorkoutSession] {
        let calendar = Calendar.current
        switch range {
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
            return workoutVM.sessions.filter { $0.date >= start }
        case .month:
            let start = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: .now)) ?? .now
            return workoutVM.sessions.filter { $0.date >= start }
        }
    }

    private var totalHoursTrained: Double {
        let minutes = sessionsInRange.reduce(0) { $0 + $1.durationMinutes }
        return Double(minutes) / 60
    }

    private var totalKcal: Int {
        sessionsInRange.reduce(0) { $0 + $1.caloriesBurned }
    }

    private var chartData: [(String, Int)] {
        switch range {
        case .week:  return workoutVM.weeklyActivityData()
        case .month: return workoutVM.monthlyActivityData()
        }
    }

    private var sectionTitle: String {
        range == .week ? "Weekly Activity" : "Monthly Activity"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PageBackground()
                HeroWord(text: "PROGRESS", size: 88, side: .leading, top: 60, opacity: 0.07)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                        summaryRow
                        weeklyActivitySection
                        historySection
                    }
                    .padding(.horizontal, AppConstants.Spacing.md)
                    .padding(.top, 140)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileToolbarButton()
                }
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            SummaryTile(value: "\(sessionsInRange.count)", label: "SESSIONS")
            SummaryTile(value: formattedHours(totalHoursTrained), label: "H TRAINED")
            SummaryTile(value: formattedKcal(totalKcal), label: "KCAL")
        }
    }

    private func formattedHours(_ h: Double) -> String {
        h >= 10 ? String(format: "%.0f", h) : String(format: "%.1f", h)
    }

    private func formattedKcal(_ kcal: Int) -> String {
        kcal >= 1000 ? String(format: "%.1fK", Double(kcal) / 1000) : "\(kcal)"
    }

    private var weeklyActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FCSectionLabel(text: sectionTitle, color: .white.opacity(0.5))
                Spacer()
                rangeToggle
            }

            WeeklyBarChartView(
                data: chartData,
                highlightLast: range == .month
            )
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(
                Image("hero_progress")
                    .resizable()
                    .scaledToFill()
                    .clipped()
            )
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
        }
    }

    private var rangeToggle: some View {
        HStack(spacing: 4) {
            ForEach(ProgressRange.allCases) { r in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { range = r }
                } label: {
                    Text(r.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(range == r ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(range == r ? Color.white : Color.clear)
                        )
                }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.06))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .clipShape(Capsule())
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FCSectionLabel(text: "History", color: .white.opacity(0.5))

            if workoutVM.sessions.isEmpty {
                EmptyStateView(
                    title: "No Sessions Yet",
                    systemImage: "figure.run.circle",
                    description: "Complete a workout to see your history here."
                )
                .padding(.top, AppConstants.Spacing.xl)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(workoutVM.sessions) { session in
                        SessionHistoryCard(session: session)
                    }
                }
            }
        }
    }
}

// MARK: - Summary tile

private struct SummaryTile: View {
    let value: String
    let label: String

    var body: some View {
        FCCard(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(FCFont.stat(34))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(label)
                    .font(FCFont.label(10))
                    .tracking(1.2)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Session history card

private struct SessionHistoryCard: View {
    let session: WorkoutSession

    var body: some View {
        FCCard(padding: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.date, format: .dateTime.day())
                        .font(FCFont.stat(34))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                    Text(session.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(FCFont.label(10))
                        .tracking(1.0)
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }
                .frame(width: 60, alignment: .leading)

                Rectangle()
                    .fill(AppConstants.Color.divider)
                    .frame(width: 1, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.workoutName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                    Text("\(session.durationMinutes) min · \(session.caloriesBurned) kcal")
                        .font(.system(size: 12))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.workoutName) on \(session.date.formatted(date: .abbreviated, time: .omitted)): \(session.durationMinutes) minutes, \(session.caloriesBurned) calories")
    }
}
