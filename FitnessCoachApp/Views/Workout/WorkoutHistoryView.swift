import SwiftUI

struct WorkoutHistoryView: View {
    let records: [WorkoutSessionRecord]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("WORKOUT HISTORY")
                            .font(FCFont.hero(34))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Close") { dismiss() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.top, 22)

                    if records.isEmpty {
                        EmptyStateView(
                            title: "No Workouts Yet",
                            systemImage: "tray",
                            description: "Completed workouts will appear here."
                        )
                        .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(records) { record in
                                HistoryRow(record: record)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.bottom, 48)
            }
        }
    }
}

private struct HistoryRow: View {
    let record: WorkoutSessionRecord

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        FCCard(padding: 14) {
            HStack(spacing: 12) {
                Text(record.intensity.emoji)
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(AppConstants.Color.cardSecondary)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                        .lineLimit(2)
                    Text(Self.dateFormatter.string(from: record.date))
                        .font(.system(size: 11))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                    HStack(spacing: 10) {
                        Label("\(Int(record.estimatedCalories)) kcal", systemImage: "flame.fill")
                        Label("\(record.durationMinutes) min", systemImage: "clock")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                }

                Spacer()

                if record.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppConstants.Color.accentDark)
                }
            }
        }
    }
}
