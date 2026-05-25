import SwiftUI

// MARK: - ViewModel

@MainActor
final class WorkoutRecommendationViewModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(WorkoutPlan)
        case error(String)
    }

    @Published var state: LoadState = .idle

    // User-tunable inputs (slide 23: intensity selector, time selector)
    @Published var availableMinutes: Int = 25
    @Published var preferredIntensity: WorkoutIntensity = .moderate
    @Published var targetCalories: Double = 500
    @Published var activeEnergyBurned: Double = 0

    private let engine: WorkoutRecommending
    private let healthProvider: HealthDataProvider

    init(engine: WorkoutRecommending = RecommendationFactory.makeEngine(),
         healthProvider: HealthDataProvider = LiveHealthDataProvider()) {
        self.engine = engine
        self.healthProvider = healthProvider
    }

    /// Loads today's active energy from HealthKit (mock or live) and triggers
    /// a recommendation. Called once on screen appear.
    func onAppear(recentSessions: [WorkoutSessionSummary]) async {
        // Best-effort HealthKit read. We don't block the recommendation if
        // it fails — the engine still works with zeros.
        if let snapshot = await healthProvider.fetchWeeklySnapshot(goalActiveKcal: Int(targetCalories)) {
            if let today = snapshot.dailyEntries.last {
                self.activeEnergyBurned = Double(today.activeKcal)
            }
            self.targetCalories = Double(snapshot.weeklyTotals.goalActiveKcalPerDay)
        }
        await recommend(recentSessions: recentSessions)
    }

    func recommend(recentSessions: [WorkoutSessionSummary]) async {
        state = .loading
        let input = RecommendationInput(
            targetCalories: targetCalories,
            activeEnergyBurned: activeEnergyBurned,
            availableMinutes: availableMinutes,
            preferredIntensity: preferredIntensity,
            bodyWeightPounds: nil,
            recentSessions: recentSessions
        )
        do {
            let plan = try await engine.recommendPlan(input: input)
            self.state = .loaded(plan)
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }
}

// MARK: - Root View

struct WorkoutRecommendationView: View {
    @StateObject private var vm = WorkoutRecommendationViewModel()
    @StateObject private var history = WorkoutHistoryStore()

    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Color.pageBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                        InputControls(vm: vm, onChange: refreshRecommendation)
                        contentForState
                    }
                    .padding(AppConstants.Spacing.md)
                }
            }
            .navigationTitle("Today's Plan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Workout history")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileToolbarButton()
                }
            }
            .sheet(isPresented: $showingHistory) {
                WorkoutHistoryView(records: history.records)
            }
            .task {
                await vm.onAppear(recentSessions: history.recentSummaries())
            }
        }
    }

    @ViewBuilder
    private var contentForState: some View {
        switch vm.state {
        case .idle:
            EmptyView()

        case .loading:
            RecommendationLoadingCard()

        case .loaded(let plan):
            RecommendedPlanCard(
                plan: plan,
                onStart: { startWorkout(plan) }
            )

        case .error(let message):
            ErrorCard(message: message, onRetry: refreshRecommendation)
        }
    }

    private func refreshRecommendation() {
        Task {
            await vm.recommend(recentSessions: history.recentSummaries())
        }
    }

    private func startWorkout(_ plan: WorkoutPlan) {
        let record = WorkoutSessionRecord(
            date: Date(),
            title: plan.title,
            estimatedCalories: plan.estimatedCalories,
            durationMinutes: plan.durationMinutes,
            intensity: plan.intensity,
            completed: true
        )
        history.add(record)
    }
}

// MARK: - Input Controls

private struct InputControls: View {
    @ObservedObject var vm: WorkoutRecommendationViewModel
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            timeRow
            intensityRow
            progressRow
        }
        .padding(AppConstants.Spacing.md)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
    }

    private var timeRow: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
            HStack {
                Label("Available time", systemImage: "clock")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(vm.availableMinutes) min")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(vm.availableMinutes) },
                    set: { vm.availableMinutes = Int($0); onChange() }
                ),
                in: 10...90, step: 5
            )
        }
    }

    private var intensityRow: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
            Label("Intensity", systemImage: "flame")
                .font(.subheadline.bold())
            Picker("Intensity", selection: Binding(
                get: { vm.preferredIntensity },
                set: { vm.preferredIntensity = $0; onChange() }
            )) {
                ForEach(WorkoutIntensity.allCases) { intensity in
                    Text("\(intensity.emoji) \(intensity.displayName)").tag(intensity)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var progressRow: some View {
        let remaining = max(0, vm.targetCalories - vm.activeEnergyBurned)
        let percent = vm.targetCalories > 0 ? vm.activeEnergyBurned / vm.targetCalories : 0
        return VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
            HStack {
                Label("Today's goal", systemImage: "target")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(Int(vm.activeEnergyBurned)) / \(Int(vm.targetCalories)) kcal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(percent, 1.0))
                .tint(percent >= 1.0 ? .green : .orange)
            if remaining > 0 {
                Text("\(Int(remaining)) kcal to go")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Goal met — let's focus on recovery.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Plan Card

private struct RecommendedPlanCard: View {
    let plan: WorkoutPlan
    let onStart: () -> Void

    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended for you")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(plan.title)
                        .font(.title2.bold())
                }
                Spacer()
                Text(plan.intensity.emoji)
                    .font(.title)
            }

            HStack(spacing: AppConstants.Spacing.lg) {
                StatPill(icon: "flame.fill", tint: .orange,
                         text: "\(Int(plan.estimatedCalories)) kcal")
                StatPill(icon: "clock", tint: AppConstants.Color.brandDark,
                         text: "\(plan.durationMinutes) min")
                StatPill(icon: "bolt.fill", tint: AppConstants.Color.brand,
                         text: plan.intensity.displayName)
            }

            Divider()

            VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                Text("Blocks")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(plan.exercises) { block in
                    HStack {
                        Text(block.role.displayName)
                            .font(.caption.bold())
                            .frame(width: 70, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(block.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(block.durationMinutes)m")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !plan.safetyNotes.isEmpty {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                    ForEach(plan.safetyNotes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(AppConstants.Spacing.sm)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.sm))
            }

            HStack(spacing: AppConstants.Spacing.sm) {
                Button {
                    showingDetail = true
                } label: {
                    Label("Details", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onStart) {
                    Label("Mark Done", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Source: \(plan.sourceProvider)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(AppConstants.Spacing.md)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
        .sheet(isPresented: $showingDetail) {
            WorkoutPlanDetailView(plan: plan, onStart: onStart)
        }
    }
}

private struct StatPill: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline.bold())
        }
    }
}

// MARK: - Loading / Error

private struct RecommendationLoadingCard: View {
    var body: some View {
        HStack {
            ProgressView()
            Text("Picking the best plan…")
                .foregroundStyle(.secondary)
        }
        .padding(AppConstants.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
    }
}

private struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AppConstants.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text("Couldn't build a plan")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(AppConstants.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
    }
}

// MARK: - Preview

struct WorkoutRecommendationView_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutRecommendationView()
    }
}
