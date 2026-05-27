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

    func onAppear(recentSessions: [WorkoutSessionSummary]) async {
        if let snapshot = await healthProvider.fetchWeeklySnapshot(goalActiveKcal: Int(targetCalories)) {
            if let today = snapshot.dailyEntries.last {
                self.activeEnergyBurned = Double(today.activeKcal)
            }
            self.targetCalories = Double(snapshot.weeklyTotals.goalActiveKcalPerDay)
        }
        // Don't auto-generate — user taps Generate when ready.
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
    @EnvironmentObject private var workoutVM: WorkoutViewModel

    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PageBackground()
                HeroWord(text: "TODAY'S PLAN", size: 64, side: .trailing, top: 60, opacity: 0.07)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                        InputControlsCard(vm: vm, onGenerate: refreshRecommendation)
                        contentForState
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
                    Button(action: { showingHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.white.opacity(0.85))
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
        Task { await vm.recommend(recentSessions: history.recentSummaries()) }
    }

    private func startWorkout(_ plan: WorkoutPlan) {
        let now = Date()
        let calories = Int(plan.estimatedCalories)

        // Save to Plan tab history
        let record = WorkoutSessionRecord(
            date: now,
            title: plan.title,
            estimatedCalories: plan.estimatedCalories,
            durationMinutes: plan.durationMinutes,
            intensity: plan.intensity,
            completed: true
        )
        history.add(record)

        // Mirror into WorkoutViewModel so Health & Progress tabs see the calories.
        workoutVM.recordExternalSession(
            workoutName: plan.title,
            durationMinutes: plan.durationMinutes,
            caloriesBurned: calories
        )

        // Write to HealthKit (live device) so the ring updates immediately.
        Task {
            try? await workoutVM.healthProvider.writeWorkoutCalories(Double(calories), date: now)
        }

        // Refresh the Plan tab's own goal ring.
        Task { await vm.onAppear(recentSessions: history.recentSummaries()) }
    }
}

// MARK: - Input Controls

private struct InputControlsCard: View {
    @ObservedObject var vm: WorkoutRecommendationViewModel
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            FCCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    FCSectionLabel(text: "Tailor your plan")
                    timeBlock
                }
            }

            FCCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    FCSectionLabel(text: "Intensity")
                    intensityBlock
                }
            }

            FCCard(padding: 18) {
                HStack(alignment: .center, spacing: 16) {
                    goalRing
                    goalCopy
                }
            }

            generateButton
        }
    }

    // MARK: Time

    private var timeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Available time")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(vm.availableMinutes)")
                        .font(FCFont.stat(30))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                        .contentTransition(.numericText())
                    Text("MIN")
                        .font(FCFont.label(11))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(vm.availableMinutes) },
                    set: { vm.availableMinutes = Int($0) }
                ),
                in: 10...90, step: 5
            )
            .tint(AppConstants.Color.accent)

            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60], id: \.self) { preset in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            vm.availableMinutes = preset
                        }
                    } label: {
                        Text("\(preset)m")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                vm.availableMinutes == preset
                                ? Color.black
                                : AppConstants.Color.mutedOnCard
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(
                                        vm.availableMinutes == preset
                                        ? AppConstants.Color.accent
                                        : AppConstants.Color.cardSecondary
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Intensity

    private var intensityBlock: some View {
        HStack(spacing: 10) {
            ForEach(WorkoutIntensity.allCases) { intensity in
                IntensityTile(
                    intensity: intensity,
                    isSelected: vm.preferredIntensity == intensity
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        vm.preferredIntensity = intensity
                    }
                }
            }
        }
    }

    // MARK: Goal

    private var percent: Double {
        guard vm.targetCalories > 0 else { return 0 }
        return min(vm.activeEnergyBurned / vm.targetCalories, 1.0)
    }

    private var goalRing: some View {
        ZStack {
            FCProgressRing(progress: percent, lineWidth: 8, size: 78)
            VStack(spacing: 0) {
                Text("\(Int(percent * 100))%")
                    .font(FCFont.stat(20))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .contentTransition(.numericText())
                Text("GOAL")
                    .font(FCFont.label(9))
                    .tracking(1.0)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
    }

    private var goalCopy: some View {
        let remaining = max(0, vm.targetCalories - vm.activeEnergyBurned)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Today's goal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppConstants.Color.mutedOnCard)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(vm.activeEnergyBurned))")
                    .font(FCFont.stat(28))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                Text("/ \(Int(vm.targetCalories))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                Text("KCAL")
                    .font(FCFont.label(10))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
            if remaining > 0 {
                Text("\(Int(remaining)) kcal to go")
                    .font(.system(size: 12))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Goal met — focus on recovery")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppConstants.Color.accentDark)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: CTA

    private var generateButton: some View {
        Button(action: onGenerate) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                Text("Generate Plan")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [AppConstants.Color.accent, AppConstants.Color.accentDark],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: AppConstants.Color.accent.opacity(0.45), radius: 16, y: 4)
            .shadow(color: AppConstants.Color.accent.opacity(0.25), radius: 4)
        }
        .disabled(vm.state == .loading)
        .opacity(vm.state == .loading ? 0.55 : 1)
    }
}

// MARK: - Intensity tile (chunky icon card)

private struct IntensityTile: View {
    let intensity: WorkoutIntensity
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch intensity {
        case .light:    return "leaf.fill"
        case .moderate: return "flame.fill"
        case .intense:  return "bolt.fill"
        }
    }

    private var tint: Color {
        switch intensity {
        case .light:    return AppConstants.Color.accent
        case .moderate: return AppConstants.Color.warn
        case .intense:  return AppConstants.Color.danger
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? .black : tint)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? tint : tint.opacity(0.12))
                    )
                    .shadow(color: isSelected ? tint.opacity(0.55) : .clear, radius: 10)

                Text(intensity.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                        ? AppConstants.Color.textOnCard
                        : AppConstants.Color.mutedOnCard
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.10) : AppConstants.Color.cardSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? tint.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(intensity.displayName) intensity")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Plan Card

private struct RecommendedPlanCard: View {
    let plan: WorkoutPlan
    let onStart: () -> Void

    @State private var showingDetail = false

    var body: some View {
        VStack(spacing: 0) {
            heroPanel
            bodyPanel
        }
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
        .shadow(color: AppConstants.Color.accent.opacity(0.25), radius: 22, y: 8)
        .sheet(isPresented: $showingDetail) {
            WorkoutPlanDetailView(plan: plan, onStart: onStart)
        }
    }

    // MARK: Hero (dark gradient with glow icon)

    private var heroPanel: some View {
        ZStack(alignment: .topLeading) {
            // Dark teal-black gradient with a soft bloom in the corner.
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.12, blue: 0.12),
                    Color(red: 0.02, green: 0.07, blue: 0.07),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [AppConstants.Color.accent.opacity(0.30), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 180
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppConstants.Color.accent)
                            .frame(width: 6, height: 6)
                            .shadow(color: AppConstants.Color.accent.opacity(0.6), radius: 4)
                        Text("RECOMMENDED FOR YOU")
                            .font(FCFont.label(11))
                            .tracking(1.2)
                            .foregroundStyle(AppConstants.Color.accent)
                    }
                    Spacer()
                    Image(systemName: planIcon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(
                            Circle().fill(AppConstants.Color.accent)
                        )
                        .shadow(color: AppConstants.Color.accent.opacity(0.55), radius: 12)
                }

                Text(plan.title.uppercased())
                    .font(FCFont.hero(30))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(plan.intensity.displayName) · Personalised plan")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))

                heroStats
                    .padding(.top, 6)
            }
            .padding(20)
        }
    }

    private var heroStats: some View {
        HStack(spacing: 8) {
            HeroStatChip(icon: "flame.fill", value: "\(Int(plan.estimatedCalories))", unit: "KCAL", tint: AppConstants.Color.danger)
            HeroStatChip(icon: "clock.fill",  value: "\(plan.durationMinutes)",       unit: "MIN",  tint: AppConstants.Color.accent)
            HeroStatChip(icon: "bolt.fill",   value: String(plan.intensity.displayName.prefix(3)).uppercased(), unit: "LVL", tint: AppConstants.Color.warn)
        }
    }

    // MARK: Body (white panel, timeline + safety + buttons)

    private var bodyPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            timeline
            if !plan.safetyNotes.isEmpty { safetyBlock }
            buttonsRow
            Text("Source: \(plan.sourceProvider)")
                .font(.system(size: 10))
                .foregroundStyle(AppConstants.Color.mutedOnCard)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppConstants.Color.cardPrimary, AppConstants.Color.cardPrimary.opacity(0.96)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { idx, block in
                BlockTimelineRow(
                    block: block,
                    isFirst: idx == 0,
                    isLast: idx == plan.exercises.count - 1
                )
            }
        }
    }

    private var planIcon: String {
        switch plan.intensity {
        case .light: return "leaf.fill"
        case .moderate: return "flame.fill"
        case .intense: return "bolt.fill"
        }
    }

    private var safetyBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppConstants.Color.accentDark)
                .frame(width: 28, height: 28)
                .background(AppConstants.Color.accent.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                ForEach(plan.safetyNotes, id: \.self) { note in
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(AppConstants.Color.textOnCard.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(AppConstants.Color.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppConstants.Color.accent.opacity(0.20), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var buttonsRow: some View {
        HStack(spacing: 12) {
            Button(action: { showingDetail = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Details")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(AppConstants.Color.textOnCard)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppConstants.Color.cardSecondary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onStart) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Mark Done")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppConstants.Color.accent)
                .clipShape(Capsule())
                .shadow(color: AppConstants.Color.accent.opacity(0.35), radius: 10)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Hero stat chip (on dark surface)

private struct HeroStatChip: View {
    let icon: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(FCFont.stat(16))
                .foregroundStyle(.white)
            Text(unit)
                .font(FCFont.label(9))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Color.white.opacity(0.08))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}

// MARK: - Timeline row

private struct BlockTimelineRow: View {
    let block: ExerciseBlock
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Connector + dot
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : AppConstants.Color.divider)
                    .frame(width: 2, height: 10)
                ZStack {
                    Circle()
                        .fill(roleTint.opacity(0.18))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(roleTint)
                        .frame(width: 10, height: 10)
                        .shadow(color: roleTint.opacity(0.5), radius: 4)
                }
                Rectangle()
                    .fill(isLast ? Color.clear : AppConstants.Color.divider)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(block.role.displayName.uppercased())
                        .font(FCFont.label(10))
                        .tracking(1.0)
                        .foregroundStyle(roleTint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(roleTint.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer()
                    Text("\(block.durationMinutes)m")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }
                Text(block.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }

    private var roleTint: Color {
        switch block.role {
        case .warmUp:   return AppConstants.Color.warn
        case .main:     return AppConstants.Color.accentDark
        case .cooldown: return AppConstants.Color.accent
        }
    }
}

// MARK: - Loading / Error

private struct RecommendationLoadingCard: View {
    var body: some View {
        FCCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(AppConstants.Color.accent)
                Text("Picking the best plan…")
                    .font(.system(size: 14))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                Spacer()
            }
        }
    }
}

private struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        FCCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(AppConstants.Color.warn)
                Text("Couldn't build a plan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                    .multilineTextAlignment(.center)
                Button("Try Again", action: onRetry)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AppConstants.Color.accent)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Preview

struct WorkoutRecommendationView_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutRecommendationView()
    }
}
