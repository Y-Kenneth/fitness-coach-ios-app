import SwiftUI

struct HealthDashboardView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @EnvironmentObject private var profileVM: ProfileViewModel
    @StateObject private var vm: HealthDashboardViewModel

    @State private var showingCoach = false
    @State private var showingCalendar = false
    @State private var snapshot: HealthSnapshot?

    private let provider: any HealthDataProvider

    init(provider: any HealthDataProvider) {
        self.provider = provider
        _vm = StateObject(wrappedValue: HealthDashboardViewModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PageBackground()
                HeroWord(text: "HEALTH", size: 88, side: .trailing, top: 60, opacity: 0.07)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                        switch vm.permissionStatus {
                        case .notDetermined:
                            ConnectHealthCard { await vm.requestPermission() }
                                .padding(.horizontal, AppConstants.Spacing.md)
                        case .denied:
                            PermissionDeniedCard()
                                .padding(.horizontal, AppConstants.Spacing.md)
                        case .unavailable:
                            HealthUnavailableCard()
                                .padding(.horizontal, AppConstants.Spacing.md)
                        case .authorized:
                            authorizedContent
                                .padding(.horizontal, AppConstants.Spacing.md)
                        }
                    }
                    .padding(.top, 140)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingCalendar = true
                    } label: {
                        Image(systemName: "calendar")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .accessibilityLabel("Pick a date")
                    .opacity(vm.permissionStatus == .authorized ? 1 : 0)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await vm.refresh()
                            await loadSnapshot()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white.opacity(0.85))
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
            .sheet(isPresented: $showingCalendar) {
                DatePickerSheet(
                    selectedDate: vm.selectedDate,
                    onSelect: { date in
                        Task { await vm.selectDate(date) }
                    }
                )
                .presentationDetents([.medium])
            }
            .task {
                await vm.onAppear()
                await loadSnapshot()
            }
            .onChange(of: workoutVM.isSessionActive) { isActive in
                // Refresh the dashboard right after a workout finishes so the
                // newly-written calories show up immediately.
                if !isActive {
                    Task { await vm.refresh() }
                }
            }
        }
    }

    @ViewBuilder
    private var authorizedContent: some View {
        ConnectionPill(connected: true)

        if vm.isLoading && vm.todayCalories == nil {
            FCCard {
                HStack {
                    ProgressView().tint(AppConstants.Color.accent)
                    Text("Reading health data…")
                        .font(.system(size: 14))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                    Spacer()
                }
            }
        } else {
            TodayActivityCard(
                kcal: vm.todayCalories,
                goal: profileVM.profile.dailyCalorieGoal,
                progress: vm.progressFraction(goal: profileVM.profile.dailyCalorieGoal),
                date: vm.selectedDate,
                isToday: vm.isViewingToday
            )

            AICoachEntryCard { showingCoach = true }

            WeeklyMetricsBento(snapshot: snapshot)
        }
    }

    private func loadSnapshot() async {
        guard vm.permissionStatus == .authorized else { return }
        let snap = await provider.fetchWeeklySnapshot(goalActiveKcal: profileVM.profile.dailyCalorieGoal)
        await MainActor.run { self.snapshot = snap }
    }
}

// MARK: - Connection pill

private struct ConnectionPill: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connected ? AppConstants.Color.accent : .gray)
                .frame(width: 6, height: 6)
                .shadow(color: AppConstants.Color.accent.opacity(0.6), radius: 4)
            Text(connected ? "APPLE HEALTH CONNECTED" : "APPLE HEALTH OFFLINE")
                .font(FCFont.label(11))
                .tracking(1.0)
                .foregroundStyle(AppConstants.Color.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppConstants.Color.accent.opacity(0.10))
        .clipShape(Capsule())
    }
}

// MARK: - Today activity hero card

private struct TodayActivityCard: View {
    let kcal: Double?
    let goal: Int
    let progress: Double
    let date: Date
    let isToday: Bool

    private var displayKcal: String {
        guard let k = kcal else { return "—" }
        return Int(k).formatted()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                FCSectionLabel(text: isToday ? "Today" : "Selected", color: .white.opacity(0.6))
                Text(displayKcal)
                    .font(FCFont.stat(96))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                Text("KCAL ACTIVE")
                    .font(FCFont.label(11))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))

                ZStack {
                    FCProgressRing(progress: progress, lineWidth: 9, size: 96)
                    VStack(spacing: 0) {
                        Text("\(Int(progress * 100))%")
                            .font(FCFont.stat(22))
                            .foregroundStyle(.white)
                        Text("of \(goal)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(
            Image("hero_health")
                .resizable()
                .scaledToFill()
                .opacity(0.75)
                .clipped()
        )
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayKcal) active kilocalories today, \(Int(progress * 100)) percent of \(goal) goal")
    }
}

// MARK: - AI Coach entry card (the one teal-gradient surface per Health screen)

private struct AICoachEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI COACH")
                        .font(FCFont.hero(24))
                        .foregroundStyle(.black)
                    Text("Personalised tips based on your week")
                        .font(.system(size: 13))
                        .foregroundStyle(.black.opacity(0.65))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.75))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [AppConstants.Color.accent, AppConstants.Color.accentDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
            .shadow(color: AppConstants.Color.accent.opacity(0.35), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI Coach. Personalised tips based on your week.")
    }
}

// MARK: - Weekly metrics bento

private struct WeeklyMetricsBento: View {
    let snapshot: HealthSnapshot?

    private var totals: WeeklyTotals? { snapshot?.weeklyTotals }
    private var stepsAvg: Int { totals?.dailyAverageSteps ?? 0 }
    private var exerciseMinAvg: Int {
        guard let t = totals, t.totalExerciseMinutes > 0 else { return 0 }
        return t.totalExerciseMinutes / 7
    }
    private var sleepHours: Double { totals?.avgSleepHours ?? 0 }
    private var restingBPM: Int { totals?.avgRestingHeartRate ?? 0 }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricTile(
                    icon: "shoeprints.fill",
                    value: stepsAvg > 0 ? stepsAvg.formatted() : "—",
                    label: "STEPS",
                    sublabel: "OF 10,000"
                )
                MetricTile(
                    icon: "flame",
                    value: exerciseMinAvg > 0 ? "\(exerciseMinAvg)" : "—",
                    label: "EXERCISE MIN",
                    sublabel: "OF 30 GOAL",
                    delta: exerciseMinAvg > 0 ? "+20%" : nil
                )
            }
            HStack(spacing: 10) {
                MetricTile(
                    icon: "moon.fill",
                    value: sleepHours > 0 ? formattedSleep(sleepHours) : "—",
                    label: "SLEEP",
                    sublabel: "AVG THIS WK"
                )
                MetricTile(
                    icon: "heart.fill",
                    value: restingBPM > 0 ? "\(restingBPM)" : "—",
                    label: "RESTING BPM",
                    sublabel: restingBPM > 0 ? "−2 VS LAST WK" : "NO DATA"
                )
            }
        }
    }

    private func formattedSleep(_ h: Double) -> String {
        let hours = Int(h)
        let minutes = Int((h - Double(hours)) * 60)
        return "\(hours)H \(String(format: "%02d", minutes))"
    }
}

private struct MetricTile: View {
    let icon: String
    let value: String
    let label: String
    let sublabel: String
    var delta: String? = nil

    var body: some View {
        FCCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.accent)
                    Spacer()
                    if let delta = delta {
                        Text(delta)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppConstants.Color.accentDark)
                    }
                }
                Text(value)
                    .font(FCFont.stat(34))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                FCSectionLabel(text: label)
                Text(sublabel)
                    .font(.system(size: 10))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(label): \(value), \(sublabel)")
    }
}

// MARK: - Permission states

private struct ConnectHealthCard: View {
    let onConnect: () async -> Void

    var body: some View {
        FCCard(padding: 22) {
            VStack(spacing: 14) {
                Image(systemName: "heart.text.clipboard")
                    .font(.system(size: 48))
                    .foregroundStyle(AppConstants.Color.danger)
                    .frame(width: 88, height: 88)
                    .background(AppConstants.Color.danger.opacity(0.12))
                    .clipShape(Circle())

                Text("CONNECT APPLE HEALTH")
                    .font(FCFont.hero(28))
                    .foregroundStyle(AppConstants.Color.textOnCard)

                Text("FitCoach reads your active calorie data to track your daily burn. Your health data stays on your device.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                    .multilineTextAlignment(.center)

                Button(action: { Task { await onConnect() } }) {
                    Text("Connect")
                }
                .buttonStyle(FCPrimaryButtonStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PermissionDeniedCard: View {
    var body: some View {
        FCCard(padding: 22) {
            VStack(spacing: 14) {
                Image(systemName: "heart.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)

                Text("HEALTH ACCESS DECLINED")
                    .font(FCFont.hero(24))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .multilineTextAlignment(.center)

                Text("Settings → Privacy & Security → Health → FitCoach → allow Active Energy.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                    .multilineTextAlignment(.center)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                }
                .buttonStyle(FCPrimaryButtonStyle())
            }
        }
    }
}

private struct HealthUnavailableCard: View {
    var body: some View {
        FCCard(padding: 22) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(AppConstants.Color.warn)
                Text("HEALTHKIT NOT AVAILABLE")
                    .font(FCFont.hero(20))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                Text("Apple Health is not supported on this device.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Date picker sheet

private struct DatePickerSheet: View {
    let selectedDate: Date
    let onSelect: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(selectedDate: Date, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.onSelect = onSelect
        _date = State(initialValue: selectedDate)
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select date",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(AppConstants.Color.accent)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle("Pick a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onSelect(date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
