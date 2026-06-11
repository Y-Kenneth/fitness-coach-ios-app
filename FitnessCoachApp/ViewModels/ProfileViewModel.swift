import SwiftUI
import Combine
import FirebaseFirestore

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: UserProfile

    private let db = Firestore.firestore()
    private var uid: String?

    init() {
        // Start blank — loadFromFirestore(uid:) fills in the right user's data.
        // Never read from UserDefaults here: the key is UID-scoped, so we can't
        // look it up until we know which user is signing in.
        profile = UserProfile()
    }

    // Called from ContentView whenever the logged-in UID changes.
    func loadFromFirestore(uid: String) {
        self.uid = uid

        // Show this user's locally-cached profile instantly while Firestore loads.
        let cacheKey = "fitness.profile.\(uid)"
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = cached
        } else {
            profile = UserProfile()
        }

        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            guard let self, let data = snapshot?.data(), error == nil else { return }
            DispatchQueue.main.async {
                self.profile = UserProfile(
                    name:             data["name"] as? String ?? self.profile.name,
                    email:            data["email"] as? String ?? "",
                    age:              data["age"] as? Int ?? self.profile.age,
                    heightCm:         data["heightCm"] as? Double ?? self.profile.heightCm,
                    weightKg:         data["weightKg"] as? Double ?? self.profile.weightKg,
                    weeklyGoalDays:   data["weeklyGoalDays"] as? Int ?? self.profile.weeklyGoalDays,
                    dailyCalorieGoal: data["dailyCalorieGoal"] as? Int ?? self.profile.dailyCalorieGoal,
                    fitnessLevel:     Difficulty(rawValue: data["fitnessLevel"] as? String ?? "") ?? self.profile.fitnessLevel
                )
                self.cacheLocally()
            }
        }
    }

    func save() {
        cacheLocally()
        guard let uid else { return }
        db.collection("users").document(uid).setData([
            "name":             profile.name,
            "email":            profile.email,
            "age":              profile.age,
            "heightCm":         profile.heightCm,
            "weightKg":         profile.weightKg,
            "weeklyGoalDays":   profile.weeklyGoalDays,
            "dailyCalorieGoal": profile.dailyCalorieGoal,
            "fitnessLevel":     profile.fitnessLevel.rawValue
        ], merge: true)
    }

    private func cacheLocally() {
        guard let uid, let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: "fitness.profile.\(uid)")
    }
}
