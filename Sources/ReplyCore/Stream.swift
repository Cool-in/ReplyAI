import Foundation

/// Reads a provider's streaming response one line at a time and collects the reply text.
struct ReplyStream {
    let provider: Provider
    private(set) var text = ""
    private var finished = false
    private var truncated = false

    init(provider: Provider) { self.provider = provider }

    private struct Kind: Decodable {
        let type: String?
    }

    private struct OpenAIDelta: Decodable {
        let delta: String
    }

    private struct Failure: Decodable {
        struct Detail: Decodable {
            let message: String?
        }
        struct Response: Decodable {
            let error: Detail?
        }
        let message: String?
        let error: Detail?
        let response: Response?

        var text: String? { message ?? error?.message ?? response?.error?.message }
    }

    private struct AnthropicEvent: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stop_reason: String?
        }
        let type: String
        let delta: Delta?
    }

    private struct OllamaChunk: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message?
        let done: Bool?
        let done_reason: String?
        let error: String?
    }

    /// Feeds one line of the response body. Returns the newly received text, if the line carried any.
    mutating func consume(_ line: String) throws -> String? {
        let payload: Substring
        if provider == .ollama {
            payload = Substring(line)
        } else {
            guard line.hasPrefix("data:") else { return nil }
            payload = line.dropFirst(5)
        }
        guard !payload.allSatisfy(\.isWhitespace) else { return nil }
        let data = Data(payload.utf8)
        let decoder = JSONDecoder()

        switch provider {
        case .openAI:
            guard let kind = (try? decoder.decode(Kind.self, from: data))?.type else { return nil }
            switch kind {
            case "response.output_text.delta":
                guard let event = try? decoder.decode(OpenAIDelta.self, from: data) else {
                    throw GenerationError.invalidResponse
                }
                return append(event.delta)
            case "response.completed":
                finished = true
            case "response.incomplete":
                finished = true
                truncated = true
            case "response.failed", "error":
                throw failure(in: data)
            default:
                break
            }
        case .anthropic:
            guard let event = try? decoder.decode(AnthropicEvent.self, from: data) else { return nil }
            switch event.type {
            case "content_block_delta":
                if event.delta?.type == "text_delta" { return append(event.delta?.text) }
            case "message_delta":
                if event.delta?.stop_reason == "max_tokens" { truncated = true }
            case "message_stop":
                finished = true
            case "error":
                throw failure(in: data)
            default:
                break
            }
        case .ollama:
            guard let chunk = try? decoder.decode(OllamaChunk.self, from: data) else {
                throw GenerationError.invalidResponse
            }
            if let message = chunk.error {
                throw HTTPGenerator.clean(message).map { GenerationError.provider(nil, $0) } ?? .invalidResponse
            }
            if chunk.done == true {
                finished = true
                if chunk.done_reason == "length" { truncated = true }
            }
            return append(chunk.message?.content)
        }
        return nil
    }

    /// Call after the last line. Returns the finished reply or explains why there isn't one.
    func finish() throws -> String {
        let reply = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if truncated { throw reply.isEmpty ? GenerationError.incomplete : GenerationError.cutShort(reply) }
        guard finished else { throw GenerationError.connectionLost }
        guard !reply.isEmpty else { throw GenerationError.emptyReply }
        return reply
    }

    private mutating func append(_ piece: String?) -> String? {
        guard let piece, !piece.isEmpty else { return nil }
        text += piece
        return piece
    }

    private func failure(in data: Data) -> GenerationError {
        let message = (try? JSONDecoder().decode(Failure.self, from: data))?.text
        return message.flatMap(HTTPGenerator.clean).map { GenerationError.provider(nil, $0) } ?? .invalidResponse
    }
}
