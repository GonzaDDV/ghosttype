import Foundation

class LLMCleanupService {
    private let apiKey: String
    private let model: String

    static let systemPrompt = """
    Clean up this dictated text. Remove filler words (um, uh, like, you know), \
    fix punctuation and capitalization. Return only the cleaned text. \
    Do not change the meaning or add anything.
    """

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    func cleanup(_ transcript: String, completion: @escaping (Result<String, Error>) -> Void) {
        var request = Self.buildRequest(apiKey: apiKey)
        request.httpBody = Self.buildRequestBody(transcript: transcript, model: model)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data, let cleaned = Self.parseResponse(from: data) else {
                completion(.failure(LLMError.invalidResponse))
                return
            }
            completion(.success(cleaned))
        }.resume()
    }

    static func buildRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    static func buildRequestBody(transcript: String, model: String) -> Data {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func parseResponse(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum LLMError: Error {
        case invalidResponse
    }
}
