import SwiftUI

struct WorkoutPlanDetailView: View {
    let plan: WorkoutPlan
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var gifs: [String: URL] = [:]   // block.id → gif URL

    private let media: ExerciseMediaProviding = RecommendationFactory.makeMediaProvider()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                    header
                    statsRow

                    ForEach(plan.exercises) { block in
                        BlockDetailCard(block: block, gifURL: gifs[block.id])
                    }

                    if !plan.safetyNotes.isEmpty {
                        safetySection
                    }

                    Button(action: {
                        onStart()
                        dismiss()
                    }) {
                        Label("Mark as Completed", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppConstants.Spacing.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, AppConstants.Spacing.sm)
                }
                .padding(AppConstants.Spacing.md)
            }
            .background(AppConstants.Color.pageBackground)
            .navigationTitle("Plan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadGIFs()
            }
        }
    }

    /// Best-effort GIF fetch — runs in the background and updates the dict
    /// as each one resolves. The UI keeps working even if every lookup fails.
    private func loadGIFs() async {
        for block in plan.exercises where gifs[block.id] == nil {
            if let url = await media.gifURL(for: block.name) {
                await MainActor.run { gifs[block.id] = url }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
            Text(plan.title)
                .font(.title.bold())
            Text("Source: \(plan.sourceProvider)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: AppConstants.Spacing.lg) {
            statTile(value: "\(Int(plan.estimatedCalories))", unit: "kcal",
                     icon: "flame.fill", tint: .orange)
            statTile(value: "\(plan.durationMinutes)", unit: "min",
                     icon: "clock", tint: AppConstants.Color.brandDark)
            statTile(value: plan.intensity.displayName, unit: "intensity",
                     icon: "bolt.fill", tint: AppConstants.Color.brand)
        }
    }

    private func statTile(value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.bold())
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppConstants.Spacing.sm)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md))
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            Label("Safety", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(plan.safetyNotes, id: \.self) { note in
                Text("• \(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppConstants.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
    }
}

private struct BlockDetailCard: View {
    let block: ExerciseBlock
    let gifURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            HStack {
                Text(block.role.displayName.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(roleTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(roleTint.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                Text("\(block.durationMinutes) min · \(Int(block.estimatedCalories)) kcal")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(block.name)
                .font(.headline)

            if let gifURL = gifURL {
                AnimatedGIFView(url: gifURL)
                    .frame(height: 180)
                    .background(AppConstants.Color.pageBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md))
                    .accessibilityLabel("Animated demonstration of \(block.name)")
            }

            if let instructions = block.instructions {
                Text(instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let muscle = block.primaryMuscle {
                Text("Focus: \(muscle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppConstants.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
    }

    private var roleTint: Color {
        switch block.role {
        case .warmUp: return .yellow
        case .main: return AppConstants.Color.brandDark
        case .cooldown: return .green
        }
    }
}
