import Foundation

@MainActor
final class HealthDashboardViewModel: ObservableObject {
    @Published var permissionStatus: HealthPermissionStatus = .notDetermined
    @Published var todayCalories: Double?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let provider: any HealthDataProvider

    init(provider: any HealthDataProvider) {
        self.provider = provider
    }

    func onAppear() async {
        permissionStatus = await provider.checkPermissionStatus()
        if permissionStatus == .authorized {
            await loadCalories()
        }
    }

    func requestPermission() async {
        permissionStatus = await provider.requestPermission()
        if permissionStatus == .authorized {
            await loadCalories()
        }
    }

    func refresh() async {
        guard permissionStatus == .authorized else { return }
        await loadCalories()
    }

    func progressFraction(goal: Int) -> Double {
        guard goal > 0, let cal = todayCalories else { return 0 }
        return min(cal / Double(goal), 1.0)
    }

    private func loadCalories() async {
        isLoading = true
        errorMessage = nil
        do {
            todayCalories = try await provider.fetchTodayActiveCalories()
        } catch {
            errorMessage = "Could not read calorie data. Please try again."
            todayCalories = nil
        }
        isLoading = false
    }
}
