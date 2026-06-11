import SwiftUI
import FirebaseCore

@main
struct FitnessCoachAppApp: App {
    @StateObject private var auth = AuthService()
    @AppStorage("devSkipLogin") private var devSkipLogin = false

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !auth.isLoggedIn && !devSkipLogin {
                    LoginView()
                } else if auth.needsOnboarding {
                    OnboardingView()
                } else {
                    ContentView()
                }
            }
            .environmentObject(auth)
            .preferredColorScheme(.dark)
        }
    }
}
