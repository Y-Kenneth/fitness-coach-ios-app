import SwiftUI

struct ActiveSessionView: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingCancelConfirm = false

    private var elapsedFormatted: String {
        let s = workoutVM.sessionElapsedSeconds
        let m = s / 60
        let sec = s % 60
        return String(format: "%02d:%02d", m, sec)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppConstants.Spacing.xl) {
                Spacer()

                if let workout = workoutVM.activeWorkout {
                    Image(systemName: workout.category.systemImage)
                        .font(.system(size: 64))
                        .foregroundStyle(AppConstants.Color.brandDark)
                        .accessibilityHidden(true)

                    Text(workout.name)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: AppConstants.Spacing.xs) {
                    Text("ELAPSED TIME")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .kerning(1.5)

                    Text(elapsedFormatted)
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Elapsed time: \(workoutVM.sessionElapsedSeconds / 60) minutes \(workoutVM.sessionElapsedSeconds % 60) seconds")
                }

                Spacer()

                VStack(spacing: AppConstants.Spacing.md) {
                    Button(action: finishSession) {
                        Label("Finish Workout", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(AppConstants.Spacing.md)
                            .background(.green)
                            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                    }
                    .frame(minHeight: 44)

                    Button("Cancel Session", role: .destructive, action: confirmCancel)
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, AppConstants.Spacing.xl)
                .padding(.bottom, AppConstants.Spacing.lg)
            }
            .navigationTitle("Active Session")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Cancel this workout?",
                isPresented: $showingCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel Session", role: .destructive, action: cancelSession)
                Button("Keep Going", role: .cancel) { }
            } message: {
                Text("Your progress for this session won't be saved.")
            }
        }
        .interactiveDismissDisabled()
    }

    private func finishSession() {
        workoutVM.finishSession()
        dismiss()
    }

    private func confirmCancel() {
        showingCancelConfirm = true
    }

    private func cancelSession() {
        workoutVM.cancelSession()
        dismiss()
    }
}
