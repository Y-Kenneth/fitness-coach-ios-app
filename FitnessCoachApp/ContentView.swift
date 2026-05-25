import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var workoutVM = WorkoutViewModel()
    @StateObject private var profileVM = ProfileViewModel()

    init() {
        Self.configureTabBarAppearance()
        Self.configureNavigationBarAppearance()
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            WorkoutRecommendationView()
                .tabItem { Label("Plan", systemImage: "sparkles.rectangle.stack.fill") }

            WorkoutListView()
                .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }

            FitnessProgressView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }

            HealthDashboardView(provider: workoutVM.healthProvider)
                .tabItem { Label("Health", systemImage: "heart.fill") }
        }
        .tint(AppConstants.Color.brand)
        .environmentObject(workoutVM)
        .environmentObject(profileVM)
    }

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0x0E/255, green: 0x0E/255, blue: 0x0E/255, alpha: 1.0)

        let brand = UIColor(red: 185/255, green: 235/255, blue: 0/255, alpha: 1.0)
        let dim = UIColor(white: 1.0, alpha: 0.45)

        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.selected.iconColor = brand
            item.selected.titleTextAttributes = [.foregroundColor: brand]
            item.normal.iconColor = dim
            item.normal.titleTextAttributes = [.foregroundColor: dim]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0x0E/255, green: 0x0E/255, blue: 0x0E/255, alpha: 1.0)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.shadowColor = .clear

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}
