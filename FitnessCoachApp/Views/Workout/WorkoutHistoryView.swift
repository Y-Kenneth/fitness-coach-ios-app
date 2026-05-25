import SwiftUI

struct WorkoutHistoryView: View {
    let records: [WorkoutSessionRecord]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(AppConstants.Color.pageBackground)
            .navigationTitle("Workout History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: AppConstants.Spacing.sm) {
                ForEach(records) { record in
                    HistoryRow(record: record)
                }
            }
            .padding(AppConstants.Spacing.md)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No workouts yet")
                .font(.headline)
            Text("Completed workouts will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(spacing: AppConstants.Spacing.md) {
            Text(record.intensity.emoji)
                .font(.title)
                .frame(width: 44, height: 44)
                .background(AppConstants.Color.pageBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text(Self.dateFormatter.string(from: record.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: AppConstants.Spacing.md) {
                    Label("\(Int(record.estimatedCalories)) kcal", systemImage: "flame.fill")
                    Label("\(record.durationMinutes) min", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if record.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(AppConstants.Spacing.md)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md))
    }
}
