import Foundation

enum HealthPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

enum HealthError: LocalizedError {
    case unavailable
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "HealthKit is not available on this device."
        case .fetchFailed(let msg): return msg
        }
    }
}

protocol HealthDataProvider {
    func checkPermissionStatus() async -> HealthPermissionStatus
    func requestPermission() async -> HealthPermissionStatus
    func fetchTodayActiveCalories() async throws -> Double
    func fetchActiveCalories(on date: Date) async throws -> Double
    func writeWorkoutCalories(_ kcal: Double, date: Date) async throws

    /// Build a 7-day health snapshot to send to the AI Coach backend.
    /// Returns `nil` if the underlying source has no usable data (e.g. simulator
    /// with no seeded Health data). Callers are expected to fall back to a mock.
    func fetchWeeklySnapshot(goalActiveKcal: Int) async -> HealthSnapshot?
}

// Default no-op so existing providers compile without immediate changes.
extension HealthDataProvider {
    func fetchWeeklySnapshot(goalActiveKcal: Int) async -> HealthSnapshot? { nil }
}
