import SwiftUI
import UIKit

// MARK: - Environment key for Form Check presentation

private struct ShowFormCheckKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var showFormCheck: () -> Void {
        get { self[ShowFormCheckKey.self] }
        set { self[ShowFormCheckKey.self] = newValue }
    }
}

// MARK: - Tab model

enum FCTab: Int, CaseIterable, Identifiable {
    case home, plan, workouts, progress, health

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .plan: return "Plan"
        case .workouts: return "Workouts"
        case .progress: return "Progress"
        case .health: return "Health"
        }
    }

    /// Symbol name when the tab is *active*.
    var activeIcon: String {
        switch self {
        case .home: return "house.fill"
        case .plan: return "star.fill"
        case .workouts: return "figure.strengthtraining.traditional"
        case .progress: return "chart.bar.fill"
        case .health: return "heart.fill"
        }
    }

    /// Symbol name when the tab is *inactive*. We keep them filled for a denser
    /// look across the bar, but you could swap to the outline versions here.
    var inactiveIcon: String {
        switch self {
        case .home: return "house"
        case .plan: return "star"
        case .workouts: return "figure.strengthtraining.traditional"
        case .progress: return "chart.bar"
        case .health: return "heart"
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var workoutVM = WorkoutViewModel()
    @StateObject private var profileVM = ProfileViewModel()
    @State private var selected: FCTab = .home
    @State private var showingFormCheck = false

    init() {
        Self.configureNavigationBarAppearance()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content stack — keep all five mounted, switch with opacity so
            // each tab's @State persists across switches (matches TabView UX).
            ZStack {
                tabContent(.home)
                    .opacity(selected == .home ? 1 : 0)
                tabContent(.plan)
                    .opacity(selected == .plan ? 1 : 0)
                tabContent(.workouts)
                    .opacity(selected == .workouts ? 1 : 0)
                tabContent(.progress)
                    .opacity(selected == .progress ? 1 : 0)
                tabContent(.health)
                    .opacity(selected == .health ? 1 : 0)
            }

            FCTabBar(selected: $selected)
        }
        .environmentObject(workoutVM)
        .environmentObject(profileVM)
        .fullScreenCover(isPresented: $showingFormCheck) {
            PoseDetectionView()
        }
        .environment(\.showFormCheck, { showingFormCheck = true })
    }

    @ViewBuilder
    private func tabContent(_ tab: FCTab) -> some View {
        switch tab {
        case .home:     HomeView()
        case .plan:     WorkoutRecommendationView()
        case .workouts: WorkoutListView()
        case .progress: FitnessProgressView()
        case .health:   HealthDashboardView(provider: workoutVM.healthProvider)
        }
    }

    /// Transparent nav bar — every screen renders its own bioluminescent
    /// background, and the nav bar must not paint a flat strip over it.
    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.shadowColor = .clear

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor.white
    }
}

// MARK: - Custom tab bar

private struct FCTabBar: View {
    @Binding var selected: FCTab
    @Namespace private var bloomNS

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FCTab.allCases) { tab in
                FCTabBarButton(
                    tab: tab,
                    isSelected: selected == tab,
                    bloomNS: bloomNS,
                    action: {
                        if selected != tab {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                selected = tab
                            }
                        }
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 22)
        .padding(.horizontal, 8)
        .background(tabBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Frosted teal-black material with a soft top highlight. Reads as part of
    /// the bioluminescent page, not as a separate UIKit slab.
    private var tabBarBackground: some View {
        ZStack {
            // Material blur layer
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            // Teal-black tint over the blur so it stays editorially dark, not
            // generic-grey like the system .ultraThinMaterial.
            AppConstants.Color.pageBase.opacity(0.65)
        }
    }
}

// MARK: - Single tab button

private struct FCTabBarButton: View {
    let tab: FCTab
    let isSelected: Bool
    let bloomNS: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Glowing bloom behind the active icon. Matched-geometry
                    // makes it slide between tabs instead of cross-fading,
                    // giving the bar a softer "particle" feel.
                    if isSelected {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        AppConstants.Color.accent.opacity(0.55),
                                        AppConstants.Color.accent.opacity(0.18),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 28
                                )
                            )
                            .frame(width: 56, height: 56)
                            .blur(radius: 6)
                            .matchedGeometryEffect(id: "tab-bloom", in: bloomNS)
                    }

                    Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .shadow(color: isSelected
                                ? AppConstants.Color.accent.opacity(0.55)
                                : .clear,
                                radius: isSelected ? 6 : 0)
                }
                .frame(height: 26)

                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(labelColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var iconColor: Color {
        isSelected ? AppConstants.Color.accent : Color.white.opacity(0.42)
    }

    private var labelColor: Color {
        isSelected ? AppConstants.Color.accent : Color.white.opacity(0.42)
    }
}
