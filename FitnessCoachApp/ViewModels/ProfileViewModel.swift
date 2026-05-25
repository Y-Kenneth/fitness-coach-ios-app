import SwiftUI
import Combine

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: UserProfile

    private let profileKey = "fitness.profile"

    init() {
        if
            let data = UserDefaults.standard.data(forKey: "fitness.profile"),
            let decoded = try? JSONDecoder().decode(UserProfile.self, from: data)
        {
            profile = decoded
        } else {
            profile = UserProfile()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }
}
