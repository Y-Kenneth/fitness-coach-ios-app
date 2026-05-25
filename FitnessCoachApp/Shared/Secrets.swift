import Foundation

/// Reads values from `Secrets.plist` in the app bundle.
///
/// The plist must be added to the Xcode target (Build Phases → Copy Bundle
/// Resources) but is gitignored so the real key is never committed.
/// See `Secrets.example.plist` for the expected structure.
enum Secrets {
    static let apiNinjasKey: String = {
        load("APINinjasKey")
    }()

    /// RapidAPI key for ExerciseDB. Used as the optional visual layer (GIFs).
    /// Leaving this blank just disables the GIFs — the rest of the app works.
    static let rapidAPIKey: String = {
        load("RapidAPIKey")
    }()

    private static func load(_ key: String) -> String {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = plist[key] as? String,
              !value.isEmpty,
              value != "PASTE_YOUR_KEY_HERE" else {
            print("⚠️ Secrets.plist missing or has placeholder for key '\(key)'. Network features that need it will fail.")
            return ""
        }
        return value
    }
}
