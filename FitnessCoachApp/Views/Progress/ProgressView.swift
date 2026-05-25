import SwiftUI

struct FitnessProgressView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                    VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                        Text("Weekly Activity")
                            .font(.title2.bold())

                        WeeklyBarChartView(data: workoutVM.weeklyActivityData())
                            .frame(height: 160)
                    }
                    .padding(.horizontal, AppConstants.Spacing.md)

                    VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                        Text("History")
                            .font(.title2.bold())
                            .padding(.horizontal, AppConstants.Spacing.md)

                        if workoutVM.sessions.isEmpty {
                            EmptyStateView(
                                title: "No Sessions Yet",
                                systemImage: "figure.run.circle",
                                description: "Complete a workout to see your history here."
                            )
                            .padding(.top, AppConstants.Spacing.xl)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(workoutVM.sessions) { session in
                                    SessionHistoryRowView(session: session)
                                    if session.id != workoutVM.sessions.last?.id {
                                        Divider()
                                            .padding(.leading, AppConstants.Spacing.md + 48 + AppConstants.Spacing.md)
                                    }
                                }
                            }
                            .background(AppConstants.Color.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                            .padding(.horizontal, AppConstants.Spacing.md)
                        }
                    }
                }
                .padding(.bottom, AppConstants.Spacing.xl)
            }
            .background(AppConstants.Color.pageBackground)
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileToolbarButton()
                }
            }
        }
    }
}

private struct SessionHistoryRowView: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: AppConstants.Spacing.md) {
            VStack(alignment: .center, spacing: 2) {
                Text(session.date, format: .dateTime.day())
                    .font(.title3.bold())
                Text(session.date, format: .dateTime.month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text(session.workoutName)
                    .font(.subheadline.bold())

                HStack(spacing: AppConstants.Spacing.sm) {
                    Label("\(session.durationMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Label("\(session.caloriesBurned) kcal", systemImage: "flame")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(AppConstants.Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.workoutName) on \(session.date.formatted(date: .abbreviated, time: .omitted)): \(session.durationMinutes) minutes, \(session.caloriesBurned) calories")
    }
}
