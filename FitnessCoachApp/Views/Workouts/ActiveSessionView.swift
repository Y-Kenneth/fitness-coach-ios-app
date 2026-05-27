import SwiftUI

struct ActiveSessionView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingCancelConfirm = false

    private var isPaused: Bool { workoutVM.isSessionPaused }

    private var elapsedFormatted: String {
        let s = workoutVM.sessionElapsedSeconds
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var body: some View {
        ZStack {
            // Active session screen is intentionally darker than the rest of the
            // app — the timer reads as the only thing on the screen.
            AppConstants.Color.pageBase.ignoresSafeArea()
            RadialGradient(
                colors: [AppConstants.Color.accent.opacity(0.10), .clear],
                center: .center, startRadius: 0, endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                exerciseHeader

                Spacer(minLength: 8)

                timerBlock

                Spacer(minLength: 8)

                hudCard
                    .padding(.horizontal, AppConstants.Spacing.md)
                    .padding(.bottom, 28)
            }
        }
        .confirmationDialog(
            "Cancel this workout?",
            isPresented: $showingCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel Session", role: .destructive) {
                workoutVM.cancelSession()
                dismiss()
            }
            Button("Keep Going", role: .cancel) { }
        } message: {
            Text("Your progress for this session won't be saved.")
        }
        .interactiveDismissDisabled()
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            FCTopBarChip(systemImage: "xmark", action: { showingCancelConfirm = true }, label: "Close")
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(AppConstants.Color.accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: AppConstants.Color.accent.opacity(0.6), radius: 4)
                Text("LIVE · \(workoutVM.activeWorkout?.name.uppercased() ?? "SESSION")")
                    .font(FCFont.label(11))
                    .tracking(1.2)
                    .foregroundStyle(AppConstants.Color.accent)
            }
            Spacer()
            // Spacer chip to keep title visually centered.
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, AppConstants.Spacing.md)
        .padding(.top, 8)
    }

    // MARK: Exercise header

    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXERCISE 1 OF 1 · BLOCK 1")
                .font(FCFont.label(11))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))
            Text(workoutVM.activeWorkout?.name.uppercased() ?? "")
                .font(FCFont.hero(48))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let workout = workoutVM.activeWorkout {
                Text("\(workout.exercises.count) exercises · \(workout.totalSets) total sets")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppConstants.Spacing.md)
        .padding(.top, 24)
    }

    // MARK: Timer block

    private var timerBlock: some View {
        VStack(spacing: 18) {
            Text(elapsedFormatted)
                .font(FCFont.stat(156))
                .foregroundStyle(.white)
                .monospacedDigit()
                .accessibilityLabel("Elapsed \(workoutVM.sessionElapsedSeconds / 60) minutes \(workoutVM.sessionElapsedSeconds % 60) seconds")

            Text(isPaused ? "PAUSED" : "ACTIVE")
                .font(FCFont.label(13))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.55))

            playPauseButton
                .padding(.top, 6)
        }
    }

    private var playPauseButton: some View {
        ZStack {
            // Outer ring (decorative).
            Circle()
                .strokeBorder(AppConstants.Color.accent.opacity(0.4), lineWidth: 2)
                .frame(width: 132, height: 132)
                .shadow(color: AppConstants.Color.accent.opacity(0.3), radius: 10)

            Button(action: { isPaused ? workoutVM.resumeSession() : workoutVM.pauseSession() }) {
                ZStack {
                    Circle()
                        .fill(AppConstants.Color.accent)
                        .frame(width: 112, height: 112)
                        .shadow(color: AppConstants.Color.accent.opacity(0.6), radius: 20)
                        .shadow(color: AppConstants.Color.accent.opacity(0.35), radius: 6)
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaused ? "Resume" : "Pause")
        }
    }

    // MARK: Bottom HUD card

    private var hudCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                hudStat(label: "TOTAL ELAPSED", value: elapsedFormatted, tint: .white)
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1, height: 38)
                hudStat(label: "STATUS",
                        value: isPaused ? "PAUSED" : "ACTIVE",
                        tint: AppConstants.Color.accent)
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1, height: 38)
                Button(action: finish) {
                    HStack(spacing: 6) {
                        Text("Finish")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(AppConstants.Color.accent)
                    .clipShape(Capsule())
                    .shadow(color: AppConstants.Color.accent.opacity(0.35), radius: 8)
                }
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 12)

            Text("Tap pause to rest · long press the timer to skip ahead")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
    }

    private func hudStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(FCFont.label(10))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(FCFont.stat(22))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private func finish() {
        workoutVM.finishSession()
        dismiss()
    }
}
