import SwiftUI

struct WorkoutDetailView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    let workout: Workout

    private var difficultyColor: Color {
        switch workout.difficulty {
        case .beginner: return AppConstants.Color.accentDark
        case .intermediate: return AppConstants.Color.warn
        case .advanced: return AppConstants.Color.danger
        }
    }

    private var heroImageName: String {
        if workout.name == "Beginner Foundations" { return "hero_beginner" }
        switch workout.category {
        case .chest:                return "hero_chest"
        case .back:                 return "hero_back"
        case .legs:                 return "hero_legs"
        case .core:                 return "hero_core"
        case .fullBody:             return "hero_fullbody"
        case .cardio:               return "hero_fullbody"
        case .shoulders, .arms:     return "hero_chest"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Hero card goes full-width — no horizontal padding
                    heroCard
                        .padding(.top, 60) // clear the custom top bar

                    // Everything below gets side padding
                    metaTiles
                        .padding(.horizontal, AppConstants.Spacing.md)
                    exercisesSection
                        .padding(.horizontal, AppConstants.Spacing.md)
                    Spacer(minLength: 100)
                }
                .padding(.bottom, 120)
            }

            stickyCTA
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { customTopBar }
        .sheet(isPresented: $workoutVM.isSessionActive) {
            ActiveSessionView()
                .environmentObject(workoutVM)
        }
    }

    private var customTopBar: some View {
        let isFav = workoutVM.isFavorite(workout)
        return HStack {
            FCTopBarChip(systemImage: "chevron.left", action: { dismiss() }, label: "Back")
            Spacer()
            FCTopBarChip(
                systemImage: isFav ? "heart.fill" : "heart",
                action: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                        workoutVM.toggleFavorite(workout)
                    }
                },
                label: isFav ? "Remove favorite" : "Add favorite",
                tint: isFav ? AppConstants.Color.danger : Color.white.opacity(0.85)
            )
        }
        .padding(.horizontal, AppConstants.Spacing.md)
        .padding(.top, 8)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Hero image — GeometryReader gives us the exact available width
            // so scaledToFill never overflows the rounded frame.
            GeometryReader { geo in
                Image(heroImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .frame(height: 220)
            .padding(.horizontal, AppConstants.Spacing.md)

            // Title / description card
            FCCard(padding: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(workout.difficulty.rawValue.uppercased())
                            .font(FCFont.label(11))
                            .tracking(1.0)
                            .foregroundStyle(difficultyColor)
                        Text("·")
                            .foregroundStyle(difficultyColor)
                        Text(workout.category.rawValue.uppercased())
                            .font(FCFont.label(11))
                            .tracking(1.0)
                            .foregroundStyle(difficultyColor)
                    }
                    Text(workout.name.uppercased())
                        .font(FCFont.hero(40))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(workout.description)
                        .font(.system(size: 14))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppConstants.Spacing.md)
        }
    }

    private var metaTiles: some View {
        HStack(spacing: 10) {
            MetaTile(value: "\(workout.durationMinutes)", label: "MIN")
            MetaTile(value: "\(workout.exercises.count)", label: "MOVES")
            MetaTile(value: "\(workout.totalSets)", label: "SETS")
        }
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FCSectionLabel(text: "Exercises", color: .white.opacity(0.5))
                .padding(.top, 4)

            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                IndexedExerciseRow(index: index + 1, exercise: exercise)
            }
        }
    }

    private var stickyCTA: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [AppConstants.Color.pageBase.opacity(0), AppConstants.Color.pageBase],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 24)
            .allowsHitTesting(false)

            Button(action: { workoutVM.startSession(for: workout) }) {
                Text("Start Workout")
            }
            .buttonStyle(FCPrimaryButtonStyle())
            .padding(.horizontal, AppConstants.Spacing.md)
            .padding(.bottom, 16)
            .background(AppConstants.Color.pageBase)
        }
        // Push the CTA above the custom tab bar (≈83pt) + safe area
        .padding(.bottom, 83)
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Components

private struct MetaTile: View {
    let value: String
    let label: String

    var body: some View {
        FCCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(FCFont.stat(32))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                Text(label)
                    .font(FCFont.label(11))
                    .tracking(1.2)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct IndexedExerciseRow: View {
    let index: Int
    let exercise: Exercise

    private var weightText: String {
        exercise.weightKg > 0 ? "\(Int(exercise.weightKg)) kg" : "Bodyweight"
    }

    var body: some View {
        FCCard(padding: 14) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index))
                    .font(FCFont.stat(22))
                    .foregroundStyle(AppConstants.Color.muted2)
                    .frame(width: 32, alignment: .leading)

                Image(systemName: exercise.muscleGroup.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.accent)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                    Text("\(exercise.sets) × \(exercise.reps) · \(weightText)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
        .accessibilityLabel("\(exercise.name): \(exercise.sets) sets of \(exercise.reps) reps, \(weightText)")
    }
}
