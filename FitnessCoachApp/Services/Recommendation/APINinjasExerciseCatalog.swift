import Foundation

/// Calls API Ninjas' Exercises endpoint and normalizes the response into
/// our internal `ExerciseTemplate` shape.
///
/// API docs: https://api-ninjas.com/api/exercises
/// Endpoint: GET https://api.api-ninjas.com/v1/exercises
/// Auth:     header `X-Api-Key: <secret>`
struct APINinjasExerciseCatalog: ExerciseCatalogProviding {

    private static let baseURL = URL(string: "https://api.api-ninjas.com/v1/exercises")!

    let apiKey: String
    let session: URLSession

    init(apiKey: String = Secrets.apiNinjasKey,
         session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetchCandidates(query: ExerciseSearchQuery) async throws -> [ExerciseTemplate] {
        guard !apiKey.isEmpty else {
            throw RecommendationError.providerFailed(underlying: NSError(
                domain: "APINinjas", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Missing API Ninjas key. Add it to Secrets.plist."]
            ))
        }

        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let t = query.type { items.append(.init(name: "type", value: apiType(for: t))) }
        if let m = query.muscle?.lowercased(), !m.isEmpty {
            items.append(.init(name: "muscle", value: m))
        }
        if let d = query.difficulty {
            items.append(.init(name: "difficulty", value: apiDifficulty(for: d)))
        }
        if let n = query.nameContains, !n.isEmpty {
            items.append(.init(name: "name", value: n))
        }
        if !items.isEmpty { components.queryItems = items }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RecommendationError.providerFailed(underlying: NSError(
                domain: "APINinjas", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Exercises endpoint returned HTTP \(http.statusCode)."]
            ))
        }

        let raw = try JSONDecoder().decode([APIExercise].self, from: data)
        return raw.map { $0.toTemplate() }
    }

    private func apiType(for type: ExerciseType) -> String {
        switch type {
        case .cardio: return "cardio"
        case .strength: return "strength"
        case .stretching: return "stretching"
        case .plyometrics: return "plyometrics"
        case .bodyweight: return "strength" // closest match in API Ninjas vocabulary
        case .mobility: return "stretching"
        case .other: return ""
        }
    }

    private func apiDifficulty(for intensity: WorkoutIntensity) -> String {
        switch intensity {
        case .light: return "beginner"
        case .moderate: return "intermediate"
        case .intense: return "expert"
        }
    }
}

// MARK: - Raw API DTO

private struct APIExercise: Decodable {
    let name: String
    let type: String?
    let muscle: String?
    let equipment: String?
    let difficulty: String?
    let instructions: String?

    func toTemplate() -> ExerciseTemplate {
        ExerciseTemplate(
            id: "ninjas-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            name: name,
            type: ExerciseType.fromAPIType(type),
            difficulty: WorkoutIntensity.fromAPIDifficulty(difficulty),
            primaryMuscle: muscle,
            equipment: (equipment?.isEmpty == false) ? [equipment!] : [],
            instructions: instructions ?? "Follow standard form for this exercise.",
            safetyInfo: nil,
            sourceProvider: "API Ninjas"
        )
    }
}
