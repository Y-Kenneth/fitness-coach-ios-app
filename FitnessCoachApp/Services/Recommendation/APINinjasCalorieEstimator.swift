import Foundation

/// Calls API Ninjas' Calories Burned endpoint and returns a single estimate.
///
/// API docs: https://api-ninjas.com/api/caloriesburned
/// Endpoint: GET https://api.api-ninjas.com/v1/caloriesburned?activity=...&weight=...&duration=...
/// Auth:     header `X-Api-Key: <secret>`
///
/// `weight` in the API is *pounds*. `duration` is in *minutes*. The endpoint
/// may return multiple matches for the same activity name (e.g. "running" has
/// many speed variants) — we just take the first.
struct APINinjasCalorieEstimator: CalorieEstimating {

    private static let baseURL = URL(string: "https://api.api-ninjas.com/v1/caloriesburned")!

    let apiKey: String
    let session: URLSession

    init(apiKey: String = Secrets.apiNinjasKey,
         session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func estimateCalories(activityName: String,
                          weightPounds: Double?,
                          durationMinutes: Int) async throws -> CalorieEstimate {
        guard !apiKey.isEmpty else {
            throw RecommendationError.providerFailed(underlying: NSError(
                domain: "APINinjas", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Missing API Ninjas key. Add it to Secrets.plist."]
            ))
        }

        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "activity", value: activityName),
            .init(name: "duration", value: String(max(durationMinutes, 1))),
        ]
        if let weight = weightPounds {
            items.append(.init(name: "weight", value: String(Int(weight.rounded()))))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RecommendationError.providerFailed(underlying: NSError(
                domain: "APINinjas", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Calories endpoint returned HTTP \(http.statusCode)."]
            ))
        }

        let raw = try JSONDecoder().decode([APICalorieEntry].self, from: data)
        guard let first = raw.first else {
            throw RecommendationError.providerFailed(underlying: NSError(
                domain: "APINinjas", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No match for activity '\(activityName)'."]
            ))
        }
        return CalorieEstimate(
            totalCalories: first.totalCalories,
            caloriesPerHour: first.caloriesPerHour,
            sourceProvider: "API Ninjas"
        )
    }
}

private struct APICalorieEntry: Decodable {
    let name: String
    let caloriesPerHour: Double
    let durationMinutes: Double
    let totalCalories: Double

    enum CodingKeys: String, CodingKey {
        case name
        case caloriesPerHour = "calories_per_hour"
        case durationMinutes = "duration_minutes"
        case totalCalories = "total_calories"
    }
}
