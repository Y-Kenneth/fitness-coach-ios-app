import SwiftUI

struct WorkoutPlanDetailView: View {
    let plan: WorkoutPlan
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var gifs: [String: URL] = [:]

    private let media: ExerciseMediaProviding = RecommendationFactory.makeMediaProvider()

    var body: some View {
        ZStack(alignment: .bottom) {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statsRow

                    FCSectionLabel(text: "Blocks", color: .white.opacity(0.5))
                        .padding(.top, 4)

                    ForEach(plan.exercises) { block in
                        BlockDetailCard(block: block, gifURL: gifs[block.id])
                    }

                    if !plan.safetyNotes.isEmpty {
                        safetySection
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.top, 60)
                .padding(.bottom, 120)
            }

            stickyCTA
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, AppConstants.Spacing.md)
            .padding(.top, 14)
        }
        .task { await loadGIFs() }
    }

    private func loadGIFs() async {
        for block in plan.exercises where gifs[block.id] == nil {
            if let url = await media.gifURL(for: block.name) {
                await MainActor.run { gifs[block.id] = url }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            FCSectionLabel(text: "Plan details", color: .white.opacity(0.5))
            Text(plan.title.uppercased())
                .font(FCFont.hero(40))
                .foregroundStyle(.white)
            Text("Source: \(plan.sourceProvider)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(value: "\(Int(plan.estimatedCalories))", unit: "KCAL")
            statTile(value: "\(plan.durationMinutes)", unit: "MIN")
            statTile(value: plan.intensity.displayName.uppercased(), unit: "INTENSITY")
        }
    }

    private func statTile(value: String, unit: String) -> some View {
        FCCard(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(FCFont.stat(26))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(FCFont.label(10))
                    .tracking(1.0)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var safetySection: some View {
        FCCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Safety", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.accentDark)
                ForEach(plan.safetyNotes, id: \.self) { note in
                    Text("• \(note)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

            Button {
                onStart()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Mark as Completed")
                }
            }
            .buttonStyle(FCPrimaryButtonStyle())
            .padding(.horizontal, AppConstants.Spacing.md)
            .padding(.bottom, 28)
            .background(AppConstants.Color.pageBase)
        }
    }
}

private struct BlockDetailCard: View {
    let block: ExerciseBlock
    let gifURL: URL?

    @State private var expanded = false

    private var roleIcon: String {
        switch block.role {
        case .warmUp:   return "figure.cooldown"
        case .main:     return "flame.fill"
        case .cooldown: return "leaf.fill"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left role-color stripe so each block is visually pinned to its phase.
            Rectangle()
                .fill(roleTint)
                .frame(width: 4)

            FCCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    headerRow
                    Text(block.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                        .fixedSize(horizontal: false, vertical: true)

                    statsRow

                    if let gifURL = gifURL {
                        AnimatedGIFView(url: gifURL)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .background(AppConstants.Color.cardSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel("Animated demonstration of \(block.name)")
                    }

                    if let instructions = block.instructions, !instructions.isEmpty {
                        instructionsView(instructions)
                    }

                    if let muscle = block.primaryMuscle {
                        focusChip(muscle)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: roleIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(roleTint)
                .frame(width: 32, height: 32)
                .background(roleTint.opacity(0.15))
                .clipShape(Circle())

            Text(block.role.displayName.uppercased())
                .font(FCFont.label(11))
                .tracking(1.2)
                .foregroundStyle(roleTint)
            Spacer()
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            DetailStatPill(icon: "clock.fill", value: "\(block.durationMinutes) min", tint: AppConstants.Color.textOnCard)
            DetailStatPill(icon: "flame.fill", value: "\(Int(block.estimatedCalories)) kcal", tint: AppConstants.Color.danger)
        }
    }

    @ViewBuilder
    private func instructionsView(_ text: String) -> some View {
        let isLong = text.count > 220
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(AppConstants.Color.mutedOnCard)
                .lineLimit(expanded || !isLong ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: 0.2), value: expanded)

            if isLong {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Show less" : "Read more")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.accentDark)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(AppConstants.Color.cardSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func focusChip(_ muscle: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "target")
                .font(.system(size: 11, weight: .semibold))
            Text("Focus: \(muscle.capitalized)")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(AppConstants.Color.accentDark)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppConstants.Color.accent.opacity(0.12))
        .clipShape(Capsule())
    }

    private var roleTint: Color {
        switch block.role {
        case .warmUp: return AppConstants.Color.warn
        case .main: return AppConstants.Color.accentDark
        case .cooldown: return AppConstants.Color.accent
        }
    }
}

private struct DetailStatPill: View {
    let icon: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppConstants.Color.textOnCard)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }
}
