import Foundation

public protocol ReplyGenerating: Sendable {
    func generate(_ prompt: ReplyPrompt) async throws -> String
}

public enum GenerationError: LocalizedError, Equatable {
    case missingModel, missingKey, cloudOllamaModel, invalidResponse, emptyReply, incomplete, http(Int)
    /// A failure the provider explained in its own words, with the HTTP status when there was one.
    case provider(Int?, String)
    /// A streamed reply that hit the length limit. Carries the text that arrived.
    case cutShort(String)
    /// The stream ended without the provider saying it had finished.
    case connectionLost

    public var errorDescription: String? {
        switch self {
        case .missingModel: "Enter a model ID in Settings first."
        case .missingKey: "Save an API key in Settings first."
        case .cloudOllamaModel: "Choose an installed local model for Ollama."
        case .invalidResponse: "The provider returned an unexpected response."
        case .emptyReply: "The provider did not return any reply text. Try a different model or revise the input."
        case .incomplete: "The model stopped before finishing the reply. Try a shorter brief or a different model."
        case .http(401), .http(403): "The provider rejected access. Check your API key and model access."
        case .http(404): "The model was not found. Check its exact ID and make sure it is available."
        case .http(429): "The provider reported a rate or quota limit. Check your account or try again shortly."
        case .http(let status): "The provider could not complete the request (HTTP \(status)). Check your model settings and try again."
        case .provider(let status?, let message): "\(GenerationError.http(status).errorDescription ?? "") The provider said: \(message)"
        case .provider(nil, let message): "The provider reported an error: \(message)"
        case .cutShort: "The reply hit the length limit and was cut short. What arrived is in the draft. Edit it, or pick a shorter length and regenerate."
        case .connectionLost: "The connection dropped before the reply finished. Your earlier draft is unchanged. Try again."
        }
    }
}

public struct HTTPGenerator: ReplyGenerating {
    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct OpenAIResponse: Decodable {
        struct Item: Decodable {
            struct Part: Decodable {
                let type: String
                let text: String?
            }
            let type: String
            let content: [Part]?
        }
        let status: String
        let output: [Item]
    }

    private struct AnthropicResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let stop_reason: String?
        let content: [Block]
    }

    private struct OllamaResponse: Decodable {
        let message: Message
        let done: Bool
        let done_reason: String?
    }

    private struct OllamaTags: Decodable {
        struct Model: Decodable {
            let name: String
        }
        let models: [Model]
    }

    /// Room for the reply plus any reasoning a model does first, which counts against the same limit.
    static let reasoningTokenLimit = 4_096

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) { completionHandler(nil) }
    }

    private let settings: Settings
    private let key: String?
    private let session: URLSession

    /// One shared session, so repeat drafts reuse the open connection instead of
    /// paying for a new TLS handshake every time.
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        // The request timeout is an idle timeout, so a slow local model can keep streaming.
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    public init(settings: Settings, key: String? = nil, session: URLSession? = nil) {
        self.settings = settings
        self.key = key
        self.session = session ?? Self.sharedSession
    }

    public func generate(_ prompt: ReplyPrompt) async throws -> String {
        let request = try request(for: prompt)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GenerationError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw Self.failure(status: http.statusCode, body: data) }
        return try decode(data)
    }

    /// Streams a reply. `onText` receives the text so far each time more arrives.
    /// Returns the finished reply, or throws if the provider failed or stopped early.
    public func stream(_ prompt: ReplyPrompt, onText: @Sendable (String) async -> Void) async throws -> String {
        let request = try request(for: prompt, streaming: true)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw GenerationError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 16_384 { break }
            }
            throw Self.failure(status: http.statusCode, body: body)
        }
        var reply = ReplyStream(provider: settings.provider)
        for try await line in bytes.lines {
            if try reply.consume(line) != nil { await onText(reply.text) }
        }
        return try reply.finish()
    }

    /// Names of the models installed in the Ollama running on this Mac.
    public static func ollamaModels(session: URLSession? = nil) async throws -> [String] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
        request.timeoutInterval = 3
        let (data, response) = try await (session ?? sharedSession).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw GenerationError.invalidResponse }
        return try decodeOllamaModels(data)
    }

    static func decodeOllamaModels(_ data: Data) throws -> [String] {
        do {
            return try JSONDecoder().decode(OllamaTags.self, from: data).models.map(\.name)
                .filter { !isCloudModel($0) }.sorted()
        } catch is DecodingError {
            throw GenerationError.invalidResponse
        }
    }

    static func isCloudModel(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasSuffix(":cloud") || name.hasSuffix("-cloud")
    }

    /// Prefers the provider's own explanation of a failed request over a bare status code.
    static func failure(status: Int, body: Data) -> GenerationError {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return .http(status) }
        let raw = (object["error"] as? [String: Any])?["message"] as? String ?? object["error"] as? String
        return raw.flatMap(clean).map { GenerationError.provider(status, $0) } ?? .http(status)
    }

    /// Collapses whitespace and bounds the length of text a provider sent back.
    static func clean(_ message: String) -> String? {
        let text = message.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(300))
    }

    func request(for prompt: ReplyPrompt, streaming: Bool = false) throws -> URLRequest {
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw GenerationError.missingModel }

        let provider = settings.provider
        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let input = ["role": "user", "content": prompt.input]
        let system = ["role": "system", "content": prompt.instructions]
        var body: [String: Any] = ["model": model]
        switch provider {
        case .openAI:
            guard let key, !key.isEmpty else { throw GenerationError.missingKey }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body["instructions"] = prompt.instructions
            body["input"] = [input]
            body["store"] = false
            body["max_output_tokens"] = Self.reasoningTokenLimit
            if streaming { body["stream"] = true }
        case .anthropic:
            guard let key, !key.isEmpty else { throw GenerationError.missingKey }
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["system"] = prompt.instructions
            body["messages"] = [input]
            body["max_tokens"] = 1_024
            if streaming { body["stream"] = true }
        case .ollama:
            guard !Self.isCloudModel(model) else { throw GenerationError.cloudOllamaModel }
            body["messages"] = [system, input]
            body["stream"] = streaming
            body["options"] = ["num_predict": Self.reasoningTokenLimit]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func decode(_ data: Data) throws -> String {
        let decoder = JSONDecoder()
        let parts: [String]
        do {
            switch settings.provider {
            case .openAI:
                let response = try decoder.decode(OpenAIResponse.self, from: data)
                guard response.status == "completed" else { throw GenerationError.incomplete }
                parts = response.output.filter { $0.type == "message" }
                    .flatMap { $0.content ?? [] }.filter { $0.type == "output_text" }.compactMap(\.text)
            case .anthropic:
                let response = try decoder.decode(AnthropicResponse.self, from: data)
                guard response.stop_reason != "max_tokens" else { throw GenerationError.incomplete }
                parts = response.content.filter { $0.type == "text" }.compactMap(\.text)
            case .ollama:
                let response = try decoder.decode(OllamaResponse.self, from: data)
                guard response.done, response.done_reason != "length" else { throw GenerationError.incomplete }
                parts = [response.message.content]
            }
        } catch is DecodingError {
            throw GenerationError.invalidResponse
        }
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GenerationError.emptyReply }
        return text
    }
}
