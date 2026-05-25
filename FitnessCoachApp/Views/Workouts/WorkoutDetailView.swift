import SwiftUI

struct WorkoutDetailView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    let workout: Workout

    @State private var showingStartConfirm = false

    private var difficultyColor: Color {
        switch workout.difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                HeaderBannerView(workout: workout, difficultyColor: difficultyColor)

                MetaRowView(workout: workout, difficultyColor: difficultyColor)
                    .padding(.horizontal, AppConstants.Spacing.md)

                Text(workout.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppConstants.Spacing.md)

                Divider()
                    .padding(.horizontal, AppConstants.Spacing.md)

                Text("Exercises (\(workout.exercises.count))")
                    .font(.title3.bold())
                    .padding(.horizontal, AppConstants.Spacing.md)

                VStack(spacing: 0) {
                    ForEach(workout.exercises) { exercise in
                        ExerciseRowView(exercise: exercise)
                            .padding(.horizontal, AppConstants.Spacing.md)
                        if exercise.id != workout.exercises.last?.id {
                            Divider()
                                .padding(.leading, AppConstants.Spacing.md + 36 + AppConstants.Spacing.md)
                        }
                    }
                }
                .background(AppConstants.Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                .padding(.horizontal, AppConstants.Spacing.md)

                Button(action: startWorkout) {
                    Label("Start Workout", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Color.onBrand)
                        .frame(maxWidth: .infinity)
                        .padding(AppConstants.Spacing.md)
                        .background(AppConstants.Color.brand)
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                }
                .padding(.horizontal, AppConstants.Spacing.md)
                .frame(minHeight: 44)
            }
            .padding(.bottom, AppConstants.Spacing.xl)
        }
        .background(AppConstants.Color.pageBackground)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $workoutVM.isSessionActive) {
            ActiveSessionView()
                .environmentObject(workoutVM)
        }
    }

    private func startWorkout() {
        workoutVM.startSession(for: workout)
    }
}

private struct HeaderBannerView: View {
    let workout: Workout
    let difficultyColor: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: workout.category.systemImage)
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.15))
                .accessibilityHidden(true)

            VStack {
                Spacer()
                HStack {
                    Text(workout.difficulty.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppConstants.Spacing.sm)
                        .padding(.vertical, AppConstants.Spacing.xs)
                        .background(difficultyColor.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.sm))
                    Spacer()
                }
                .padding(AppConstants.Spacing.md)
            }
        }
        .frame(height: 180)
        .accessibilityHidden(true)
    }
}

private struct MetaRowView: View {
    let workout: Workout
    let difficultyColor: Color

    var body: some View {
        HStack(spacing: AppConstants.Spacing.xl) {
            MetaItemView(systemImage: "clock", value: "\(workout.durationMinutes)", label: "min")
            MetaItemView(systemImage: "list.bullet", value: "\(workout.exercises.count)", label: "exercises")
            MetaItemView(systemImage: "arrow.up.right", value: "\(workout.totalSets)", label: "total sets")
        }
    }
}

private struct MetaItemView: View {
    let systemImage: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: AppConstants.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(AppConstants.Color.brandDark)
                .accessibilityHidden(true)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}
