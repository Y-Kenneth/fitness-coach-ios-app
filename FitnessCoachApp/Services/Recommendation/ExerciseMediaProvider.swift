import Foundation

protocol ExerciseMediaProviding {
    func gifURL(for exerciseName: String) async -> URL?
}

struct ExerciseDBMediaProvider: ExerciseMediaProviding {

    private static let host = "exercisedb.p.rapidapi.com"
    private static let baseURL = "https://exercisedb.p.rapidapi.com"

    let apiKey: String
    let session: URLSession

    init(apiKey: String = Secrets.rapidAPIKey, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func gifURL(for exerciseName: String) async -> URL? {
        guard !apiKey.isEmpty else {
            print("🔴 ExerciseDB: RapidAPIKey is empty — skipping GIF for '\(exerciseName)'")
            return nil
        }

        let searchTerm = Self.searchTerm(for: exerciseName)
        guard !searchTerm.isEmpty,
              let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(Self.baseURL)/exercises/name/\(encoded)?limit=1&offset=0") else {
            return nil
        }

        print("🟡 ExerciseDB: '\(exerciseName)' → searching '\(searchTerm)'")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue(Self.host, forHTTPHeaderField: "X-RapidAPI-Host")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("🟡 ExerciseDB: HTTP \(http.statusCode) for '\(searchTerm)'")
                guard (200..<300).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? "(no body)"
                    print("🔴 ExerciseDB: error body: \(body)")
                    return nil
                }
            }
            let entries = try JSONDecoder().decode([ExerciseDBEntry].self, from: data)
            print("🟡 ExerciseDB: \(entries.count) result(s) for '\(searchTerm)'")
            guard let first = entries.first,
                  let urlString = first.gifUrl,
                  let gifURL = URL(string: urlString) else {
                print("🔴 ExerciseDB: no gifUrl in response for '\(searchTerm)'")
                return nil
            }
            print("🟢 ExerciseDB: GIF found for '\(exerciseName)' → \(urlString)")
            return gifURL
        } catch {
            print("🔴 ExerciseDB: lookup failed for '\(searchTerm)': \(error.localizedDescription)")
            return nil
        }
    }

    // Maps recommender display names to ExerciseDB-friendly search keywords.
    // ExerciseDB uses short lowercase names like "squat", "push up", "leg press".
    private static func searchTerm(for name: String) -> String {
        let lower = name.lowercased()

        if lower.contains("warm") { return "jumping jack" }
        if lower.contains("cooldown") || lower.contains("cool down") || lower.contains("stretch") { return "stretch" }

        let cleaned = lower
            .replacingOccurrences(of: "single-leg ", with: "")
            .replacingOccurrences(of: "single leg ", with: "")
            .replacingOccurrences(of: "dumbbell ", with: "")
            .replacingOccurrences(of: "barbell ", with: "")
            .replacingOccurrences(of: "cable ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = cleaned.components(separatedBy: " ").filter { !$0.isEmpty }
        return words.prefix(2).joined(separator: " ")
    }
}

struct NoMediaProvider: ExerciseMediaProviding {
    func gifURL(for exerciseName: String) async -> URL? { nil }
}

private struct ExerciseDBEntry: Decodable {
    let id: String?
    let name: String?
    let gifUrl: String?
    let target: String?
    let bodyPart: String?
    let equipment: String?
}
