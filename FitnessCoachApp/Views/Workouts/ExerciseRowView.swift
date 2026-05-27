import SwiftUI

// Legacy exercise row — retained for any caller that still uses it directly.
// New screens use IndexedExerciseRow inside WorkoutDetailView.
struct ExerciseRowView: View {
    let exercise: Exercise

    private var weightText: String {
        exercise.weightKg > 0 ? "\(Int(exercise.weightKg)) kg" : "Bodyweight"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: exercise.muscleGroup.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppConstants.Color.accent)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                Text("\(exercise.sets) × \(exercise.reps) · \(weightText)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                if !exercise.notes.isEmpty {
                    Text(exercise.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(AppConstants.Color.muted2)
                        .italic()
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name): \(exercise.sets) sets of \(exercise.reps) reps, \(weightText)")
    }
}
