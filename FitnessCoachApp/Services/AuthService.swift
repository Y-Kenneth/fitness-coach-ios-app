import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@MainActor
final class AuthService: ObservableObject {

    @Published var user: FirebaseAuth.User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var needsOnboarding = false

    private var handle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                if let uid = user?.uid {
                    self?.checkOnboardingStatus(uid: uid)
                } else {
                    self?.needsOnboarding = false
                }
            }
        }
    }

    private func checkOnboardingStatus(uid: String) {
        db.collection("users").document(uid).getDocument { [weak self] snapshot, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let completed = snapshot?.data()?["onboardingComplete"] as? Bool ?? false
                self.needsOnboarding = !completed
            }
        }
    }

    func completeOnboarding() {
        needsOnboarding = false
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var isLoggedIn: Bool { user != nil }
    var uid: String? { user?.uid }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = friendlyError(error)
        }
        isLoading = false
    }

    // MARK: - Register

    func signUp(email: String, password: String, name: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let uid = result.user.uid
            try await db.collection("users").document(uid).setData([
                "name": name,
                "email": email,
                "onboardingComplete": false
            ])
            needsOnboarding = true
        } catch {
            errorMessage = friendlyError(error)
        }
        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: - Error helper

    private func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        switch AuthErrorCode.Code(rawValue: nsError.code) {
        case .invalidEmail:              return "Invalid email address."
        case .wrongPassword:             return "Incorrect password."
        case .userNotFound:              return "No account found with this email."
        case .invalidCredential:         return "Email or password is incorrect."
        case .emailAlreadyInUse:         return "This email is already registered."
        case .weakPassword:              return "Password must be at least 6 characters."
        case .networkError:              return "Network error. Check your connection."
        default:                         return error.localizedDescription
        }
    }
}
