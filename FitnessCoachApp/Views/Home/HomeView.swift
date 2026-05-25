import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @EnvironmentObject private var profileVM: ProfileViewModel
    @State private var showingWorkoutPicker = false
    @State private var showingFormCheck = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                    GreetingBannerView(
                        name: profileVM.profile.name,
                        weeklyGoal: profileVM.profile.weeklyGoalDays,
                        completedThisWeek: workoutVM.totalWorkoutsThisWeek
                    )

                    Text("This Week")
                        .font(.title2.bold())
                        .padding(.horizontal, AppConstants.Spacing.md)

                    LazyVGrid(columns: columns, spacing: AppConstants.Spacing.md) {
                        StatCardView(
                            title: "Workouts",
                            value: "\(workoutVM.totalWorkoutsThisWeek)",
                            unit: "sessions",
                            systemImage: "figure.strengthtraining.traditional",
                            tint: AppConstants.Color.brandDark
                        )
                        StatCardView(
                            title: "Calories",
                            value: "\(workoutVM.totalCaloriesThisWeek)",
                            unit: "kcal",
                            systemImage: "flame.fill",
                            tint: .orange
                        )
                        StatCardView(
                            title: "Time",
                            value: "\(workoutVM.totalMinutesThisWeek)",
                            unit: "minutes",
                            systemImage: "clock.fill",
                            tint: AppConstants.Color.brand
                        )
                        StatCardView(
                            title: "Goal",
                            value: "\(workoutVM.totalWorkoutsThisWeek)/\(profileVM.profile.weeklyGoalDays)",
                            unit: "days",
                            systemImage: "target",
                            tint: .green
                        )
                    }
                    .padding(.horizontal, AppConstants.Spacing.md)

                    Text("Quick Start")
                        .font(.title2.bold())
                        .padding(.horizontal, AppConstants.Spacing.md)

                    QuickStartScrollView()

                    Button(action: { showingFormCheck = true }) {
                        HStack(spacing: AppConstants.Spacing.md) {
                            Image(systemName: "figure.mixed.cardio")
                                .font(.title2)
                                .foregroundStyle(AppConstants.Color.onBrand)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.2), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Form Check (Beta)")
                                    .font(.headline)
                                    .foregroundStyle(AppConstants.Color.onBrand)
                                Text("Real-time pose analysis with your camera")
                                    .font(.caption)
                                    .foregroundStyle(AppConstants.Color.onBrand.opacity(0.75))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppConstants.Color.onBrand.opacity(0.7))
                        }
                        .padding(AppConstants.Spacing.md)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(colors: [.teal, .green],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppConstants.Spacing.md)
                    .accessibilityLabel("Form Check, beta")
                    .accessibilityHint("Opens a camera view that analyzes your exercise form")
                }
                .padding(.bottom, AppConstants.Spacing.lg)
            }
            .background(AppConstants.BrandBackground())
            .navigationTitle("FitCoach")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileToolbarButton()
                }
            }
            .sheet(isPresented: $workoutVM.isSessionActive) {
                ActiveSessionView()
                    .environmentObject(workoutVM)
            }
            .fullScreenCover(isPresented: $showingFormCheck) {
                PoseDetectionView()
            }
        }
    }
}

private struct GreetingBannerView: View {
    let name: String
    let weeklyGoal: Int
    let completedThisWeek: Int

    private var progress: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(Double(completedThisWeek) / Double(weeklyGoal), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            Text("Hello, \(name) 💪")
                .font(.title.bold())
                .foregroundStyle(AppConstants.Color.onBrand)

            Text(progress >= 1 ? "Weekly goal complete! Amazing work." : "Keep pushing — you've got this.")
                .font(.subheadline)
                .foregroundStyle(AppConstants.Color.onBrand.opacity(0.75))

            ProgressView(value: progress)
                .tint(AppConstants.Color.onBrand)
                .padding(.top, AppConstants.Spacing.xs)
                .accessibilityLabel("Weekly goal: \(completedThisWeek) of \(weeklyGoal) days completed")
        }
        .padding(AppConstants.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
        .padding(.horizontal, AppConstants.Spacing.md)
        .padding(.top, AppConstants.Spacing.sm)
    }
}

private struct QuickStartScrollView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: AppConstants.Spacing.md) {
                ForEach(workoutVM.workouts.prefix(4)) { workout in
                    QuickStartCardView(workout: workout)
                }
            }
            .padding(.horizontal, AppConstants.Spacing.md)
        }
        .scrollIndicators(.hidden)
    }
}

private struct QuickStartCardView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            Image(systemName: workout.category.systemImage)
                .font(.title2)
                .foregroundStyle(AppConstants.Color.onBrand)
                .accessibilityHidden(true)

            Text(workout.name)
                .font(.headline)
                .foregroundStyle(AppConstants.Color.onBrand)
                .lineLimit(2)

            Text("\(workout.durationMinutes) min · \(workout.difficulty.rawValue)")
                .font(.caption)
                .foregroundStyle(AppConstants.Color.onBrand.opacity(0.7))

            Spacer()

            Button("Start", action: { workoutVM.startSession(for: workout) })
                .font(.subheadline.bold())
                .foregroundStyle(AppConstants.Color.onBrand)
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.vertical, AppConstants.Spacing.sm)
                .background(.white.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(AppConstants.Spacing.md)
        .frame(width: 160, height: 200)
        .background(
            LinearGradient(
                colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.name), \(workout.durationMinutes) minutes, \(workout.difficulty.rawValue)")
        .accessibilityHint("Double tap to start this workout")
    }
}
