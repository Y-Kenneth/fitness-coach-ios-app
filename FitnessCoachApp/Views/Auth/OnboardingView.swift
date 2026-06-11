import SwiftUI
import FirebaseFirestore

struct OnboardingView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var step = 0
    @State private var isSaving = false

    // Step 1 — body metrics
    @State private var age = 25
    @State private var heightCm = 170
    @State private var weightKg = 70

    // Step 2 — fitness goals
    @State private var fitnessLevel: Difficulty = .beginner
    @State private var weeklyGoalDays = 4
    @State private var dailyCalorieGoal = 500

    private let db = Firestore.firestore()

    var body: some View {
        ZStack {
            PageBackground()
            HeroWord(text: "SETUP", size: 94, side: .trailing, top: 24)

            VStack(spacing: 0) {
                stepIndicator
                    .padding(.top, 64)

                Group {
                    if step == 0 {
                        step1View
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        step2View
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: step)
            }
        }
    }

    // MARK: Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<2) { i in
                Capsule()
                    .fill(i == step ? AppConstants.Color.accent : Color.white.opacity(0.25))
                    .frame(width: i == step ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            }
        }
    }

    // MARK: Step 1 — Body metrics

    private var step1View: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Body")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Helps us tailor workouts to your fitness needs.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 32)

                VStack(spacing: 14) {
                    OnboardingMetricRow(label: "Age",    value: $age,      unit: "yrs",  range: 10...100,  step: 1)
                    OnboardingMetricRow(label: "Height", value: $heightCm, unit: "cm",   range: 120...250, step: 1)
                    OnboardingMetricRow(label: "Weight", value: $weightKg, unit: "kg",   range: 30...250,  step: 1)
                }

                Button("Continue") {
                    withAnimation { step = 1 }
                }
                .buttonStyle(FCPrimaryButtonStyle())
                .padding(.top, 8)
            }
            .padding(.horizontal, AppConstants.Spacing.md)
            .padding(.bottom, 48)
        }
    }

    // MARK: Step 2 — Fitness goals

    private var step2View: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Goals")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Set targets you can adjust at any time.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 32)

                VStack(spacing: 14) {
                    // Fitness level picker
                    OnboardingDarkCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Fitness Level")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                                .tracking(0.8)

                            HStack(spacing: 8) {
                                ForEach(Difficulty.allCases) { level in
                                    Button(level.rawValue) {
                                        fitnessLevel = level
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(fitnessLevel == level ? .black : .white.opacity(0.7))
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        fitnessLevel == level
                                            ? AppConstants.Color.accent
                                            : Color.white.opacity(0.10)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: fitnessLevel)
                                }
                            }
                        }
                    }

                    OnboardingMetricRow(label: "Weekly Goal",       value: $weeklyGoalDays,   unit: "days", range: 1...7,      step: 1)
                    OnboardingMetricRow(label: "Daily Calorie Goal", value: $dailyCalorieGoal, unit: "kcal", range: 100...2000, step: 50)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation { step = 0 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 52, height: 52)
                            .background(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await saveAndFinish() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.black)
                            } else {
                                Text("Let's Go!")
                            }
                        }
                    }
                    .buttonStyle(FCPrimaryButtonStyle())
                    .disabled(isSaving)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, AppConstants.Spacing.md)
            .padding(.bottom, 48)
        }
    }

    // MARK: Save

    private func saveAndFinish() async {
        guard let uid = auth.uid else { return }
        isSaving = true
        do {
            try await db.collection("users").document(uid).setData([
                "age":               age,
                "heightCm":          Double(heightCm),
                "weightKg":          Double(weightKg),
                "fitnessLevel":      fitnessLevel.rawValue,
                "weeklyGoalDays":    weeklyGoalDays,
                "dailyCalorieGoal":  dailyCalorieGoal,
                "onboardingComplete": true
            ], merge: true)
            auth.completeOnboarding()
        } catch {
            isSaving = false
        }
    }
}

// MARK: - Dark card container

private struct OnboardingDarkCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Metric row

private struct OnboardingMetricRow: View {
    let label: String
    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        OnboardingDarkCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.8)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(value)")
                            .font(FCFont.stat(36))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
                        Text(unit)
                            .font(FCFont.label(13))
                            .tracking(1.0)
                            .foregroundStyle(AppConstants.Color.accent)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    metricButton(systemImage: "minus", tinted: false) {
                        let next = value - step
                        if next >= range.lowerBound { value = next }
                    }
                    metricButton(systemImage: "plus", tinted: true) {
                        let next = value + step
                        if next <= range.upperBound { value = next }
                    }
                }
            }
        }
    }

    private func metricButton(systemImage: String, tinted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tinted ? .black : .white)
                .frame(width: 40, height: 40)
                .background(tinted ? AppConstants.Color.accent : Color.white.opacity(0.14))
                .clipShape(Circle())
                .shadow(color: tinted ? AppConstants.Color.accent.opacity(0.4) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}
