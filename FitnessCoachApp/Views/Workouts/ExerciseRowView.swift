import SwiftUI

struct ExerciseRowView: View {
    let exercise: Exercise
    private var weightText: String {
        exercise.weightKg > 0 ? "\(Int(exercise.weightKg)) kg" : "Bodyweight"
    }

    var body: some View {
        HStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: exercise.muscleGroup.systemImage)
                .font(.title3)
                .foregroundStyle(AppConstants.Color.brandDark)
                .frame(width: 36, height: 36)
                .background(AppConstants.Color.brand.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.sm))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text(exercise.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text("\(exercise.sets) sets × \(exercise.reps) reps · \(weightText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !exercise.notes.isEmpty {
                    Text(exercise.notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }

            Spacer()
        }
        .padding(.vertical, AppConstants.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name): \(exercise.sets) sets of \(exercise.reps) reps, \(weightText)")
    }
}
