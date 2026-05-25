import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profileVM: ProfileViewModel
    @EnvironmentObject private var workoutVM: WorkoutViewModel

    var body: some View {
        NavigationStack {
            Form {
                ProfileHeaderSection()
                PersonalInfoSection()
                FitnessGoalSection()
                StatsSection()
            }
            .navigationTitle("Profile")
        }
    }
}

private struct ProfileHeaderSection: View {
    @EnvironmentObject private var profileVM: ProfileViewModel

    var body: some View {
        Section {
            HStack(spacing: AppConstants.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [AppConstants.Color.brand, AppConstants.Color.brandDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)

                    Text(profileVM.profile.name.prefix(1).uppercased())
                        .font(.title.bold())
                        .foregroundStyle(AppConstants.Color.onBrand)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                    Text(profileVM.profile.name)
                        .font(.title3.bold())
                    Text(profileVM.profile.fitnessLevel.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("BMI: \(profileVM.profile.bmi, format: .number.precision(.fractionLength(1))) · \(profileVM.profile.bmiCategory)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, AppConstants.Spacing.sm)
        }
    }
}

private struct PersonalInfoSection: View {
    @EnvironmentObject private var profileVM: ProfileViewModel

    var body: some View {
        Section("Personal Info") {
            LabeledContent("Name") {
                TextField("Your name", text: $profileVM.profile.name)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: profileVM.profile.name) { _ in profileVM.save() }
            }

            LabeledContent("Age") {
                TextField("Age", value: $profileVM.profile.age, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .onChange(of: profileVM.profile.age) { _ in profileVM.save() }
            }

            LabeledContent("Height (cm)") {
                TextField("Height", value: $profileVM.profile.heightCm, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .onChange(of: profileVM.profile.heightCm) { _ in profileVM.save() }
            }

            LabeledContent("Weight (kg)") {
                TextField("Weight", value: $profileVM.profile.weightKg, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .onChange(of: profileVM.profile.weightKg) { _ in profileVM.save() }
            }
        }
    }
}

private struct FitnessGoalSection: View {
    @EnvironmentObject private var profileVM: ProfileViewModel

    var body: some View {
        Section("Fitness Goals") {
            Picker("Fitness Level", selection: $profileVM.profile.fitnessLevel) {
                ForEach(Difficulty.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .onChange(of: profileVM.profile.fitnessLevel) { _ in profileVM.save() }

            LabeledContent("Weekly Goal") {
                Stepper(
                    "\(profileVM.profile.weeklyGoalDays) days",
                    value: $profileVM.profile.weeklyGoalDays,
                    in: 1...7
                )
                .onChange(of: profileVM.profile.weeklyGoalDays) { _ in profileVM.save() }
            }

            LabeledContent("Daily Calorie Goal") {
                Stepper(
                    "\(profileVM.profile.dailyCalorieGoal) kcal",
                    value: $profileVM.profile.dailyCalorieGoal,
                    in: 100...2000,
                    step: 50
                )
                .onChange(of: profileVM.profile.dailyCalorieGoal) { _ in profileVM.save() }
            }
        }
    }
}

private struct StatsSection: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel

    var body: some View {
        Section("All-Time Stats") {
            LabeledContent("Total Sessions", value: "\(workoutVM.sessions.count)")
            LabeledContent("Total Minutes") {
                Text("\(workoutVM.sessions.reduce(0) { $0 + $1.durationMinutes })")
            }
            LabeledContent("Total Calories") {
                Text("\(workoutVM.sessions.reduce(0) { $0 + $1.caloriesBurned }) kcal")
            }
        }
    }
}
