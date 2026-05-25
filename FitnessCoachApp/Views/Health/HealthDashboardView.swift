import SwiftUI

struct HealthDashboardView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @EnvironmentObject private var profileVM: ProfileViewModel
    @StateObject private var vm: HealthDashboardViewModel
    @State private var showingCoach = false

    init(provider: any HealthDataProvider) {
        _vm = StateObject(wrappedValue: HealthDashboardViewModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppConstants.Spacing.lg) {
                    switch vm.permissionStatus {
                    case .notDetermined:
                        ConnectHealthView { await vm.requestPermission() }
                    case .denied:
                        PermissionDeniedView()
                    case .unavailable:
                        HealthUnavailableView()
                    case .authorized:
                        authorizedContent
                    }
                }
                .padding(AppConstants.Spacing.md)
            }
            .background(AppConstants.Color.pageBackground)
            .navigationTitle("Health Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh health data")
                    .disabled(vm.isLoading)
                    .opacity(vm.permissionStatus == .authorized ? 1 : 0)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileToolbarButton()
                }
            }
            .sheet(isPresented: $showingCoach) {
                A2ACoachingView()
            }
            .task {
                await vm.onAppear()
            }
        }
    }

    @ViewBuilder
    private var authorizedContent: some View {
        ConnectionStatusBadge(status: .authorized)

        if vm.isLoading {
            ProgressView("Reading health data…")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let message = vm.errorMessage {
            ErrorBannerView(message: message) {
                Task { await vm.refresh() }
            }
        } else {
            CalorieDashboardCard(
                todayCalories: vm.todayCalories,
                goal: profileVM.profile.dailyCalorieGoal,
                progress: vm.progressFraction(goal: profileVM.profile.dailyCalorieGoal)
            )

            FitCoachCaloriesCard(
                allTimeKcal: workoutVM.sessions.reduce(0) { $0 + $1.caloriesBurned },
                sessionCount: workoutVM.sessions.count
            )

            RecommendationEntryCard {
                showingCoach = true
            }
        }
    }
}

// MARK: - Connect Health View

private struct ConnectHealthView: View {
    let onConnect: () async -> Void

    var body: some View {
        VStack(spacing: AppConstants.Spacing.lg) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 64))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(spacing: AppConstants.Spacing.sm) {
                Text("Connect Apple Health")
                    .font(.title2.bold())

                Text("FitCoach reads your active calorie data to track your daily burn and help you reach your goal. Your health data stays on your device and is never used for advertising.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await onConnect() }
            } label: {
                Label("Connect Apple Health", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(AppConstants.Spacing.md)
                    .background(.red)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
            }
            .frame(minHeight: 44)
        }
        .padding(AppConstants.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
    }
}

// MARK: - Permission Denied View

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: AppConstants.Spacing.lg) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: AppConstants.Spacing.sm) {
                Text("Health Access Declined")
                    .font(.title3.bold())

                Text("To see your calorie data, go to Settings → Privacy & Security → Health → FitCoach and allow access to Active Energy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppConstants.Color.brandDark)
            }
            .frame(minHeight: 44)
        }
        .padding(AppConstants.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Health Unavailable View

private struct HealthUnavailableView: View {
    var body: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("HealthKit Not Available")
                .font(.title3.bold())

            Text("Apple Health is not supported on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppConstants.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
    }
}

// MARK: - Connection Status Badge

private struct ConnectionStatusBadge: View {
    let status: HealthPermissionStatus

    private var label: String {
        status == .authorized ? "Health Connected" : "Health Disconnected"
    }

    private var color: Color {
        status == .authorized ? .green : .secondary
    }

    var body: some View {
        HStack(spacing: AppConstants.Spacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, AppConstants.Spacing.sm)
        .accessibilityLabel(label)
    }
}

// MARK: - Calorie Dashboard Card

private struct CalorieDashboardCard: View {
    let todayCalories: Double?
    let goal: Int
    let progress: Double

    private var caloriesDisplay: String {
        guard let cal = todayCalories else { return "—" }
        return cal.formatted(.number.precision(.fractionLength(0)))
    }

    private var progressPercent: String {
        "\(Int(progress * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
            Text("Today's Activity")
                .font(.title2.bold())

            HStack(alignment: .bottom, spacing: AppConstants.Spacing.xs) {
                Text(caloriesDisplay)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(todayCalories == nil ? .secondary : .primary)
                    .contentTransition(.numericText())

                Text("kcal active")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, AppConstants.Spacing.sm)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                todayCalories == nil
                    ? "No active calories recorded yet today"
                    : "\(caloriesDisplay) active kilocalories today"
            )

            VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                HStack {
                    Text("Daily Goal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(goal) kcal · \(progressPercent)")
                        .font(.subheadline.bold())
                        .foregroundStyle(progress >= 1 ? .green : .primary)
                }

                ProgressView(value: progress)
                    .tint(progress >= 1 ? .green : .orange)
                    .accessibilityLabel("Goal progress: \(progressPercent) of \(goal) kilocalories")
            }

            if todayCalories == nil {
                Label("No active calories recorded today yet.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppConstants.Spacing.lg)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
    }
}

// MARK: - Error Banner

private struct ErrorBannerView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text("Could Not Load Data")
                    .font(.subheadline.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Retry", action: onRetry)
                .font(.caption.bold())
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(AppConstants.Spacing.md)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
    }
}

// MARK: - FitCoach Calories Card

private struct FitCoachCaloriesCard: View {
    let allTimeKcal: Int
    let sessionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            HStack {
                Label("FitCoach Workouts", systemImage: "figure.strengthtraining.traditional")
                    .font(.headline)
                Spacer()
                Text("All-time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppConstants.Spacing.sm)
                    .padding(.vertical, AppConstants.Spacing.xs)
                    .background(.orange.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack(alignment: .bottom, spacing: AppConstants.Spacing.xs) {
                Text(allTimeKcal.formatted())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text("kcal logged")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, AppConstants.Spacing.xs)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(allTimeKcal.formatted()) kilocalories logged across all FitCoach workouts")

            Divider()

            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Calories burned across \(sessionCount) FitCoach session\(sessionCount == 1 ? "" : "s"). Written to Apple Health after each workout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppConstants.Spacing.lg)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Recommendation Entry Card

private struct RecommendationEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppConstants.Spacing.md) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(AppConstants.Color.onBrand)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                    Text("AI Coach Recommendation")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Color.onBrand)
                    Text("See personalised tips based on your activity")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Color.onBrand.opacity(0.75))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(AppConstants.Color.onBrand.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(AppConstants.Spacing.lg)
            .background(
                LinearGradient(
                    colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
        }
        .accessibilityLabel("Get AI Coach Recommendation")
        .accessibilityHint("Opens the AI coaching screen")
    }
}
