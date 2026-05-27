import Foundation

@MainActor
final class HealthDashboardViewModel: ObservableObject {
    @Published var permissionStatus: HealthPermissionStatus = .notDetermined
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @Published var selectedDateCalories: Double?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let provider: any HealthDataProvider

    init(provider: any HealthDataProvider) {
        self.provider = provider
    }

    var todayCalories: Double? { selectedDateCalories }

    var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
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

    func selectDate(_ date: Date) async {
        selectedDate = Calendar.current.startOfDay(for: date)
        await loadCalories()
    }

    func progressFraction(goal: Int) -> Double {
        guard goal > 0, let cal = selectedDateCalories else { return 0 }
        return min(cal / Double(goal), 1.0)
    }

    private func loadCalories() async {
        isLoading = true
        errorMessage = nil
        do {
            selectedDateCalories = try await provider.fetchActiveCalories(on: selectedDate)
        } catch {
            errorMessage = "Could not read calorie data. Please try again."
            selectedDateCalories = nil
        }
        isLoading = false
    }
}
