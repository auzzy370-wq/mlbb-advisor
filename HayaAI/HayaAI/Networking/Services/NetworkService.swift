import Foundation

// MARK: - Network Service
final class NetworkService: Sendable {

    private let session: URLSession
    private let baseURL: String = "https://api.hayaai.app/v1"
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    // MARK: - Hero Database

    func fetchHeroDatabase(patchVersion: String) async throws -> Data {
        let url = URL(string: "\(baseURL)/heroes?patch=\(patchVersion)")!
        return try await fetchData(from: url)
    }

    // MARK: - Meta

    func fetchMetaData(patchVersion: String) async throws -> Data {
        let url = URL(string: "\(baseURL)/meta?patch=\(patchVersion)")!
        return try await fetchData(from: url)
    }

    // MARK: - AI Explanation (OpenAI)

    func fetchExplanation(prompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are an expert Mobile Legends draft analyst."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 300,
            "temperature": 0.7
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    // MARK: - Private

    private func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode)
        }
        return data
    }
}

// MARK: - OpenAI Response
private struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Network Errors
enum NetworkError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response."
        case .httpError(let code): return "HTTP error \(code)."
        case .decodingError(let msg): return "Decoding error: \(msg)"
        case .noData: return "No data received."
        }
    }
}
