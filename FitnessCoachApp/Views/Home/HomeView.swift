import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @EnvironmentObject private var profileVM: ProfileViewModel
    @Environment(\.showFormCheck) private var showFormCheck

    private var weekDescriptor: String {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: Date())
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return "\(f.string(from: Date())) · Week \(week)"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PageBackground()

                HeroWord(text: "FITCOACH", size: 96, side: .leading, top: 60)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                        greeting
                            .padding(.horizontal, AppConstants.Spacing.md)

                        bentoGrid
                            .padding(.horizontal, AppConstants.Spacing.md)

                        quickStartSection

                        formCheckCTA
                            .padding(.horizontal, AppConstants.Spacing.md)
                    }
                    .padding(.top, 130)
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
            .sheet(isPresented: $workoutVM.isSessionActive) {
                ActiveSessionView()
                    .environmentObject(workoutVM)
            }
        }
    }

    // MARK: Greeting block

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hello, \(profileVM.profile.name)")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(weekDescriptor)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    // MARK: Bento grid

    private var bentoGrid: some View {
        HStack(alignment: .top, spacing: 10) {
            WorkoutsThisWeekCard(
                count: workoutVM.totalWorkoutsThisWeek,
                goal: profileVM.profile.weeklyGoalDays
            )
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                CaloriesStatCard(kcal: workoutVM.totalCaloriesThisWeek)
                TimeStatCard(totalMinutes: workoutVM.totalMinutesThisWeek)
                WeeklyGoalPaceCard(
                    completed: workoutVM.totalWorkoutsThisWeek,
                    goal: profileVM.profile.weeklyGoalDays
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Quick Start

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                FCSectionLabel(text: "Quick Start", color: .white.opacity(0.5))
                Spacer()
                HStack(spacing: 4) {
                    Text("See all")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, AppConstants.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(workoutVM.workouts.prefix(5)) { workout in
                        QuickStartCardView(workout: workout)
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.md)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Form Check CTA

    private var formCheckCTA: some View {
        Button(action: { showFormCheck() }) {
            FCCard(padding: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.accent)
                        .frame(width: 48, height: 48)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("FORM CHECK")
                                .font(FCFont.hero(26))
                                .foregroundStyle(AppConstants.Color.textOnCard)
                            BetaPill()
                        }
                        Text("Real-time pose analysis")
                            .font(.system(size: 13))
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Form Check, beta")
        .accessibilityHint("Opens a camera view that analyzes your exercise form")
    }
}

// MARK: - Bento components

private struct WorkoutsThisWeekCard: View {
    let count: Int
    let goal: Int

    var body: some View {
        ZStack(alignment: .leading) {
            // Background hero image
            Image("hero_home")
                .resizable()
                .scaledToFill()
                .frame(minHeight: 280)
                .clipped()

            // Dark overlay so text is readable
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.25)],
                startPoint: .bottom,
                endPoint: .top
            )

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.accent)

                Spacer(minLength: 10)

                FCSectionLabel(text: "Workouts\nThis Week")

                Text(String(format: "%02d", count))
                    .font(FCFont.stat(78))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("of \(goal) sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 2)

                Spacer(minLength: 12)

                HStack(spacing: 4) {
                    ForEach(0..<max(goal, 1), id: \.self) { idx in
                        Capsule()
                            .fill(idx < count
                                  ? AppConstants.Color.accent
                                  : Color.white.opacity(0.25))
                            .frame(height: 4)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
        .frame(minHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of \(goal) workouts completed this week")
    }
}

private struct CaloriesStatCard: View {
    let kcal: Int

    var body: some View {
        FCCard(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("CALORIES")
                        .font(FCFont.label(9))
                        .tracking(1.0)
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }

                Text(kcal.formatted())
                    .font(FCFont.stat(34))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("KCAL · THIS WK")
                    .font(FCFont.label(9))
                    .tracking(0.8)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityLabel("\(kcal) kilocalories burned this week")
    }
}

private struct TimeStatCard: View {
    let totalMinutes: Int

    private var hours: Int { totalMinutes / 60 }
    private var minutes: Int { totalMinutes % 60 }

    var body: some View {
        FCCard(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.textOnCard.opacity(0.7))
                    Spacer()
                    Text("TIME")
                        .font(FCFont.label(9))
                        .tracking(1.0)
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(hours)")
                        .font(FCFont.stat(34))
                    Text("H")
                        .font(FCFont.stat(18))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                    Text(String(format: "%02d", minutes))
                        .font(FCFont.stat(34))
                }
                .foregroundStyle(AppConstants.Color.textOnCard)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("ACTIVE MIN")
                    .font(FCFont.label(9))
                    .tracking(0.8)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityLabel("\(hours) hours \(minutes) minutes active this week")
    }
}

private struct WeeklyGoalPaceCard: View {
    let completed: Int
    let goal: Int

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(completed) / Double(goal), 1.0)
    }

    var body: some View {
        FCCard(padding: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    FCProgressRing(progress: progress, lineWidth: 5, size: 48)
                    Text("\(completed)/\(goal)")
                        .font(FCFont.stat(13))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 1) {
                    Text("WEEKLY")
                        .font(FCFont.label(9))
                        .tracking(1.0)
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                    Text("Goal pace")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(progress >= 1 ? "Complete" : "On track")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.accentDark)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Weekly goal pace: \(completed) of \(goal) completed")
    }
}

// MARK: - Quick Start card

private struct QuickStartCardView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    let workout: Workout

    private var difficultyTint: Color {
        switch workout.difficulty {
        case .beginner: return AppConstants.Color.accentDark
        case .intermediate: return AppConstants.Color.warn
        case .advanced: return AppConstants.Color.danger
        }
    }

    private var estimatedCalories: Int {
        Int(Double(workout.durationMinutes) * 10.5)
    }

    var body: some View {
        Button(action: { workoutVM.startSession(for: workout) }) {
            FCCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(workout.difficulty.rawValue.uppercased())
                            .font(FCFont.label(10))
                            .tracking(1.0)
                            .foregroundStyle(difficultyTint)
                        Spacer()
                        Image(systemName: workout.category.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppConstants.Color.accent)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.04))
                            .clipShape(Circle())
                    }

                    Spacer(minLength: 4)

                    Text(workout.name.uppercased())
                        .font(FCFont.hero(26))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(workout.durationMinutes) MIN · \(estimatedCalories) KCAL")
                            .font(FCFont.label(10))
                            .tracking(0.6)
                    }
                    .foregroundStyle(AppConstants.Color.mutedOnCard)

                    Spacer(minLength: 4)

                    HStack(spacing: 6) {
                        Text("Start")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 18, height: 18)
                            .background(AppConstants.Color.accent)
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black)
                    .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 168, height: 208)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.name), \(workout.durationMinutes) minutes, \(workout.difficulty.rawValue)")
        .accessibilityHint("Double tap to start this workout")
    }
}

// MARK: - BETA pill

private struct BetaPill: View {
    var body: some View {
        Text("BETA")
            .font(FCFont.label(9))
            .tracking(0.6)
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppConstants.Color.accent)
            .clipShape(Capsule())
    }
}
