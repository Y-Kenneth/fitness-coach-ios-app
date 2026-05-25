import SwiftUI

struct WorkoutListView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FilterChipRowView(selected: $workoutVM.selectedFilter)

                if workoutVM.filteredWorkouts.isEmpty {
                    EmptyStateView(
                        title: "No Workouts",
                        systemImage: "figure.run",
                        description: "No workouts match this filter."
                    )
                } else {
                    List(workoutVM.filteredWorkouts) { workout in
                        NavigationLink(value: workout) {
                            WorkoutRowView(workout: workout)
                        }
                        .listRowBackground(AppConstants.Color.cardBackground)
                        .listRowSeparatorTint(.secondary.opacity(0.3))
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: Workout.self) { workout in
                        WorkoutDetailView(workout: workout)
                            .environmentObject(workoutVM)
                    }
                }
            }
            .background(AppConstants.Color.pageBackground)
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileToolbarButton()
                }
            }
        }
    }
}

private struct FilterChipRowView: View {
    @Binding var selected: MuscleGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppConstants.Spacing.sm) {
                FilterChip(label: "All", isSelected: selected == nil) {
                    selected = nil
                }
                ForEach(MuscleGroup.allCases) { group in
                    FilterChip(label: group.rawValue, isSelected: selected == group) {
                        selected = selected == group ? nil : group
                    }
                }
            }
            .padding(.horizontal, AppConstants.Spacing.md)
            .padding(.vertical, AppConstants.Spacing.sm)
        }
        .scrollIndicators(.hidden)
        .background(AppConstants.Color.pageBackground)
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(isSelected ? AppConstants.Color.onBrand : .primary)
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.vertical, AppConstants.Spacing.sm)
                .background(isSelected ? AppConstants.Color.brand : AppConstants.Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
        }
        .frame(minHeight: 44)
    }
}

private struct WorkoutRowView: View {
    let workout: Workout

    private var difficultyColor: Color {
        switch workout.difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }

    var body: some View {
        HStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: workout.category.systemImage)
                .font(.title2)
                .foregroundStyle(AppConstants.Color.brandDark)
                .frame(width: 48, height: 48)
                .background(AppConstants.Color.brand.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                Text(workout.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: AppConstants.Spacing.sm) {
                    Label("\(workout.durationMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(workout.difficulty.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(difficultyColor)
                }

                Text("\(workout.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, AppConstants.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(workout.name), \(workout.durationMinutes) minutes, \(workout.difficulty.rawValue), \(workout.exercises.count) exercises")
    }
}
