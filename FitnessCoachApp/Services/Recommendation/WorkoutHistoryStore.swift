import Foundation
import Combine

/// Simple JSON-on-disk store for completed workout sessions.
/// Replaces SwiftData (which is iOS 17+) so the app can stay on iOS 16.4.
@MainActor
final class WorkoutHistoryStore: ObservableObject {

    @Published private(set) var records: [WorkoutSessionRecord] = []

    private let fileURL: URL

    init(filename: String = "workout_history.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Make sure the directory exists.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(filename)
        load()
    }

    // MARK: - Public API

    func add(_ record: WorkoutSessionRecord) {
        records.insert(record, at: 0)
        save()
    }

    func delete(_ record: WorkoutSessionRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    /// Compact summaries of the last N sessions, for the recommender's
    /// novelty score.
    func recentSummaries(limit: Int = 10) -> [WorkoutSessionSummary] {
        Array(records.prefix(limit)).map { $0.toSummary() }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder.iso8601.decode([WorkoutSessionRecord].self, from: data)
            self.records = decoded
        } catch {
            print("⚠️ WorkoutHistoryStore failed to load: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder.iso8601.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("⚠️ WorkoutHistoryStore failed to save: \(error.localizedDescription)")
        }
    }
}

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
