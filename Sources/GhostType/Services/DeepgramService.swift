import Foundation

struct DeepgramTranscriptResult {
    let transcript: String
    let isFinal: Bool
    let confidence: Double
}

class DeepgramService {
    private var webSocketTask: URLSessionWebSocketTask?
    private let apiKey: String
    var onTranscript: ((DeepgramTranscriptResult) -> Void)?
    var onError: ((Error) -> Void)?

    private var finalTranscriptParts: [String] = []

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    static func buildWebSocketURL(apiKey: String) -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "api.deepgram.com"
        components.path = "/v1/listen"
        components.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "interim_results", value: "false"),
            URLQueryItem(name: "model", value: "nova-2")
        ]
        return components.url!
    }

    func startStreaming() {
        finalTranscriptParts = []
        let url = Self.buildWebSocketURL(apiKey: apiKey)
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
    }

    func sendAudio(_ data: Data) {
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error = error {
                self?.onError?(error)
            }
        }
    }

    func stopStreaming(completion: @escaping (String) -> Void) {
        let closeMessage = "{\"type\": \"CloseStream\"}"
        webSocketTask?.send(.string(closeMessage)) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let fullTranscript = self?.finalTranscriptParts.joined(separator: " ") ?? ""
                completion(fullTranscript)
                self?.webSocketTask?.cancel(with: .normalClosure, reason: nil)
                self?.webSocketTask = nil
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let parsed = Self.parseTranscript(from: data) {
                        if parsed.isFinal && !parsed.transcript.isEmpty {
                            self?.finalTranscriptParts.append(parsed.transcript)
                        }
                        self?.onTranscript?(parsed)
                    }
                default:
                    break
                }
                self?.receiveMessage()
            case .failure(let error):
                self?.onError?(error)
            }
        }
    }

    static func parseTranscript(from data: Data) -> DeepgramTranscriptResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let first = alternatives.first,
              let transcript = first["transcript"] as? String else {
            return nil
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let confidence = first["confidence"] as? Double ?? 0.0

        return DeepgramTranscriptResult(
            transcript: transcript,
            isFinal: isFinal,
            confidence: confidence
        )
    }
}
