import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profileVM: ProfileViewModel
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground()
            HeroWord(text: "PROFILE", size: 94, side: .leading, top: 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerRow
                    BMIBand(bmi: profileVM.profile.bmi, category: profileVM.profile.bmiCategory)
                    allTimeStats
                    personalInfoSection
                    fitnessGoalsSection
                }
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 40, height: 4)
                .padding(.top, 8)
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if UIImage(named: "profile_photo") != nil {
                    Image("profile_photo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(AppConstants.Color.accent, lineWidth: 2))
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppConstants.Color.accent, AppConstants.Color.accentDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 76, height: 76)
                        Text(profileVM.profile.name.prefix(1).uppercased())
                            .font(FCFont.hero(40))
                            .foregroundStyle(.black)
                    }
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(profileVM.profile.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    Text("\(profileVM.profile.fitnessLevel.rawValue.uppercased()) · AGE \(profileVM.profile.age)")
                        .font(FCFont.label(11))
                        .tracking(1.0)
                        .foregroundStyle(AppConstants.Color.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppConstants.Color.accent.opacity(0.12))
                .clipShape(Capsule())
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close profile")
        }
        .padding(.top, 100)
    }

    // MARK: All-time stats

    private var totalMinutes: Int {
        workoutVM.sessions.reduce(0) { $0 + $1.durationMinutes }
    }
    private var totalKcal: Int {
        workoutVM.sessions.reduce(0) { $0 + $1.caloriesBurned }
    }
    private func formattedKcal(_ kcal: Int) -> String {
        kcal >= 1000 ? String(format: "%.0fK", Double(kcal) / 1000) : "\(kcal)"
    }

    private var allTimeStats: some View {
        HStack(spacing: 10) {
            ProfileStatTile(value: "\(workoutVM.sessions.count)", label: "TOTAL\nSESSIONS")
            ProfileStatTile(value: "\(totalMinutes / 60)", label: "HOURS\nTRAINED")
            ProfileStatTile(value: formattedKcal(totalKcal), label: "KCAL\nBURNED")
        }
    }

    // MARK: Personal info

    private var personalInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FCSectionLabel(text: "Personal Info", color: .white.opacity(0.5))

            FCCard(padding: 0) {
                VStack(spacing: 0) {
                    EditableInfoRow(
                        label: "Height",
                        valueText: Binding(
                            get: { "\(Int(profileVM.profile.heightCm)) cm" },
                            set: { newVal in
                                let digits = newVal.filter(\.isNumber)
                                if let v = Double(digits) {
                                    profileVM.profile.heightCm = v
                                    profileVM.save()
                                }
                            }
                        )
                    )
                    InfoDivider()
                    EditableInfoRow(
                        label: "Weight",
                        valueText: Binding(
                            get: { "\(Int(profileVM.profile.weightKg)) kg" },
                            set: { newVal in
                                let digits = newVal.filter(\.isNumber)
                                if let v = Double(digits) {
                                    profileVM.profile.weightKg = v
                                    profileVM.save()
                                }
                            }
                        )
                    )
                    InfoDivider()
                    EditableInfoRow(
                        label: "Age",
                        valueText: Binding(
                            get: { "\(profileVM.profile.age)" },
                            set: { newVal in
                                if let v = Int(newVal.filter(\.isNumber)) {
                                    profileVM.profile.age = v
                                    profileVM.save()
                                }
                            }
                        )
                    )
                    InfoDivider()
                    EditableInfoRow(
                        label: "Name",
                        valueText: $profileVM.profile.name,
                        onCommit: { profileVM.save() }
                    )
                }
            }
        }
    }

    // MARK: Fitness goals

    private var fitnessGoalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FCSectionLabel(text: "Fitness Goals", color: .white.opacity(0.5))

            FCCard(padding: 0) {
                VStack(spacing: 0) {
                    FitnessLevelRow(selected: $profileVM.profile.fitnessLevel) {
                        profileVM.save()
                    }
                    InfoDivider()
                    StepperRow(
                        label: "Weekly goal",
                        value: Binding(
                            get: { profileVM.profile.weeklyGoalDays },
                            set: { v in
                                profileVM.profile.weeklyGoalDays = v
                                profileVM.save()
                            }
                        ),
                        range: 1...7,
                        step: 1,
                        unit: "DAYS"
                    )
                    InfoDivider()
                    StepperRow(
                        label: "Daily kcal goal",
                        value: Binding(
                            get: { profileVM.profile.dailyCalorieGoal },
                            set: { v in
                                profileVM.profile.dailyCalorieGoal = v
                                profileVM.save()
                            }
                        ),
                        range: 100...2000,
                        step: 50,
                        unit: "KCAL"
                    )
                }
            }
        }
    }
}

// MARK: - Pieces

private struct ProfileStatTile: View {
    let value: String
    let label: String

    var body: some View {
        FCCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(FCFont.stat(32))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(label)
                    .font(FCFont.label(10))
                    .tracking(1.2)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                    .multilineTextAlignment(.leading)
            }
        }
        .accessibilityLabel("\(value) \(label.replacingOccurrences(of: "\n", with: " "))")
    }
}

private struct BMIBand: View {
    let bmi: Double
    let category: String

    /// Position the marker along the [0,1] band. 18.5 → start, 35 → end.
    private var fraction: CGFloat {
        let clamped = max(15, min(35, bmi))
        return CGFloat((clamped - 15) / 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("BMI · ")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(String(format: "%.1f", bmi))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(" · ")
                    .foregroundStyle(.white.opacity(0.4))
                Text(category.lowercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.accent)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "5DA9E9"),
                                    AppConstants.Color.accent,
                                    AppConstants.Color.warn,
                                    AppConstants.Color.danger
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(height: 6)

                    Capsule()
                        .fill(.white)
                        .frame(width: 4, height: 18)
                        .offset(x: proxy.size.width * fraction - 2)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
            }
            .frame(height: 18)
        }
    }
}

private struct EditableInfoRow: View {
    let label: String
    @Binding var valueText: String
    var onCommit: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppConstants.Color.mutedOnCard)
            Spacer()
            TextField("", text: $valueText, onCommit: { onCommit?() })
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppConstants.Color.textOnCard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppConstants.Color.muted2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct InfoDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppConstants.Color.divider)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

private struct FitnessLevelRow: View {
    @Binding var selected: Difficulty
    var onChange: () -> Void

    var body: some View {
        HStack {
            Text("Fitness level")
                .font(.system(size: 14))
                .foregroundStyle(AppConstants.Color.mutedOnCard)
            Spacer()
            Menu {
                ForEach(Difficulty.allCases) { level in
                    Button(level.rawValue) {
                        selected = level
                        onChange()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selected.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.muted2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct StepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppConstants.Color.mutedOnCard)
            Spacer()
            HStack(spacing: 12) {
                StepperChip(systemImage: "minus", tinted: false) {
                    let next = value - step
                    if next >= range.lowerBound { value = next }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(FCFont.stat(20))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                    Text(unit)
                        .font(FCFont.label(10))
                        .tracking(1.0)
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }
                .frame(minWidth: 78)
                StepperChip(systemImage: "plus", tinted: true) {
                    let next = value + step
                    if next <= range.upperBound { value = next }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct StepperChip: View {
    let systemImage: String
    let tinted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tinted ? .black : AppConstants.Color.textOnCard)
                .frame(width: 32, height: 32)
                .background(tinted ? AppConstants.Color.accent : AppConstants.Color.cardSecondary)
                .clipShape(Circle())
                .shadow(color: tinted ? AppConstants.Color.accent.opacity(0.35) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}
