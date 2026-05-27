import SwiftUI

struct WorkoutListView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @State private var showFavoritesOnly = false

    private var visibleWorkouts: [Workout] {
        showFavoritesOnly
            ? workoutVM.filteredWorkouts.filter { workoutVM.isFavorite($0) }
            : workoutVM.filteredWorkouts
    }

    private var emptyDescription: String {
        showFavoritesOnly
            ? "Tap the heart on any workout to save it here."
            : "No workouts match this filter."
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PageBackground()
                HeroWord(text: "WORKOUTS", size: 84, side: .leading, top: 60, opacity: 0.07)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                        FilterChipRowView(
                            selected: $workoutVM.selectedFilter,
                            showFavoritesOnly: $showFavoritesOnly,
                            favoritesCount: workoutVM.favoriteWorkoutIDs.count
                        )
                        .padding(.top, 140)

                        if visibleWorkouts.isEmpty {
                            EmptyStateView(
                                title: showFavoritesOnly ? "No Favorites Yet" : "No Workouts",
                                systemImage: showFavoritesOnly ? "heart" : "figure.run",
                                description: emptyDescription
                            )
                            .padding(.horizontal, AppConstants.Spacing.md)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(visibleWorkouts) { workout in
                                    NavigationLink(value: workout) {
                                        WorkoutRowCard(
                                            workout: workout,
                                            isFavorite: workoutVM.isFavorite(workout)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, AppConstants.Spacing.md)
                        }
                    }
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .navigationDestination(for: Workout.self) { workout in
                    WorkoutDetailView(workout: workout)
                        .environmentObject(workoutVM)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .accessibilityLabel("Search workouts")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileToolbarButton()
                }
            }
        }
    }
}

// MARK: - Filter chip row

private struct FilterChipRowView: View {
    @Binding var selected: MuscleGroup?
    @Binding var showFavoritesOnly: Bool
    let favoritesCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FavoritesFilterChip(
                    isSelected: showFavoritesOnly,
                    count: favoritesCount
                ) {
                    showFavoritesOnly.toggle()
                }
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
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

private struct FavoritesFilterChip: View {
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: .semibold))
                Text("Favorites")
                    .font(.system(size: 13, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? Color.black.opacity(0.18)
                                    : AppConstants.Color.danger.opacity(0.25)
                            )
                        )
                }
            }
            .foregroundStyle(
                isSelected
                    ? AppConstants.Color.textOnCard
                    : AppConstants.Color.danger
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(isSelected ? Color.white : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.clear : AppConstants.Color.danger.opacity(0.5),
                    lineWidth: 1
                )
            )
        }
        .frame(minHeight: 36)
        .accessibilityLabel(isSelected ? "Showing favorites only" : "Show favorites only")
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? AppConstants.Color.textOnCard : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : Color.white.opacity(0.2),
                        lineWidth: 1
                    )
                )
        }
        .frame(minHeight: 36)
    }
}

// MARK: - Workout row card

private struct WorkoutRowCard: View {
    let workout: Workout
    var isFavorite: Bool = false

    private var difficultyColor: Color {
        switch workout.difficulty {
        case .beginner: return AppConstants.Color.accentDark
        case .intermediate: return AppConstants.Color.warn
        case .advanced: return AppConstants.Color.danger
        }
    }

    private var thumbnailName: String {
        if workout.name == "Beginner Foundations" { return "hero_beginner" }
        switch workout.category {
        case .chest:            return "hero_chest"
        case .back:             return "hero_back"
        case .legs:             return "hero_legs"
        case .core:             return "hero_core"
        case .fullBody:         return "hero_fullbody"
        case .cardio:           return "hero_fullbody"
        case .shoulders, .arms: return "hero_chest"
        }
    }

    var body: some View {
        FCCard(padding: 14) {
            HStack(spacing: 14) {
                Image(thumbnailName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(workout.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppConstants.Color.textOnCard)
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppConstants.Color.danger)
                                .accessibilityLabel("Favorite")
                        }
                    }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(difficultyColor)
                            .frame(width: 6, height: 6)
                        Text(workout.difficulty.rawValue)
                            .font(.system(size: 12))
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                        Text("·")
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                        Text("\(workout.exercises.count) exercises")
                            .font(.system(size: 12))
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                        Text("·")
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                        Text("\(workout.durationMinutes) min")
                            .font(.system(size: 12))
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(workout.name), \(workout.durationMinutes) minutes, \(workout.difficulty.rawValue), \(workout.exercises.count) exercises")
    }
}
