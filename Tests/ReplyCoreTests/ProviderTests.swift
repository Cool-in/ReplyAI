import Foundation
import Testing
@testable import ReplyCore

private func settings(_ provider: Provider, model: String = "test-model") -> Settings {
    var settings = Settings()
    settings.provider = provider
    settings.model = model
    return settings
}

private final class ProviderStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let status: Int
        let response: String
        switch url.path {
        case "/v1/responses":
            status = 200
            response = #"{"status":"completed","output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"OpenAI draft"}]}]}"#
        case "/v1/messages":
            status = 200
            response = #"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":"internal"},{"type":"text","text":"Claude draft"}]}"#
        case "/api/chat":
            status = 200
            response = #"{"done":true,"done_reason":"stop","message":{"role":"assistant","content":"Ollama draft"}}"#
        default:
            status = 404
            response = "{}"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status,
                            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test(arguments: [Provider.openAI, .anthropic, .ollama])
func providerSendsCorrectRequestAndDecodesDraft(_ provider: Provider) async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ProviderStub.self]
    let session = URLSession(configuration: config)
    defer { session.finishTasksAndInvalidate() }

    let prompt = ReplyPrompt(source: "How does it work?", brief: "Explain offline sync.")
    let generator = HTTPGenerator(settings: settings(provider), key: "fixture-key", session: session)
    let request = try generator.request(for: prompt)
    let data = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(request.url == provider.endpoint)
    #expect(request.httpMethod == "POST")
    #expect(body["model"] as? String == "test-model")
    #expect(!String(decoding: data, as: UTF8.self).contains("fixture-key"))
    switch provider {
    case .openAI:
        #expect(body["store"] as? Bool == false)
        #expect(body["instructions"] as? String == prompt.instructions)
        #expect((body["input"] as? [[String: String]])?.first?["content"] == prompt.input)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        #expect(try await generator.generate(prompt) == "OpenAI draft")
    case .anthropic:
        #expect(body["system"] as? String == prompt.instructions)
        #expect((body["messages"] as? [[String: String]])?.first?["content"] == prompt.input)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
        #expect(try await generator.generate(prompt) == "Claude draft")
    case .ollama:
        #expect(request.url?.host == "127.0.0.1")
        #expect(body["stream"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["content"] } == [prompt.instructions, prompt.input])
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(try await generator.generate(prompt) == "Ollama draft")
    }
}

@Test func rejectsIncompleteEmptyAndMisconfiguredReplies() throws {
    let prompt = ReplyPrompt(source: "Question")
    let openAI = HTTPGenerator(settings: settings(.openAI))
    #expect(throws: GenerationError.missingKey) { try openAI.request(for: prompt) }
    #expect(throws: GenerationError.incomplete) {
        try openAI.decode(Data(#"{"status":"incomplete","output":[]}"#.utf8))
    }
    #expect(throws: GenerationError.emptyReply) {
        try openAI.decode(Data(#"{"status":"completed","output":[{"type":"reasoning"}]}"#.utf8))
    }
    #expect(throws: GenerationError.invalidResponse) { try openAI.decode(Data("not JSON".utf8)) }
    #expect(throws: GenerationError.missingModel) {
        try HTTPGenerator(settings: settings(.ollama, model: " ")).request(for: prompt)
    }
    #expect(throws: GenerationError.cloudOllamaModel) {
        try HTTPGenerator(settings: settings(.ollama, model: "example:cloud")).request(for: prompt)
    }
}

private let streamFixtures: [Provider: String] = [
    .openAI: """
    event: response.created
    data: {"type":"response.created","response":{"status":"in_progress"}}

    event: response.reasoning_summary_text.delta
    data: {"type":"response.reasoning_summary_text.delta","delta":"internal"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"OpenAI "}

    data: {"type":"response.output_text.delta","delta":"draft"}

    data: {"type":"response.completed","response":{"status":"completed"}}

    """,
    .anthropic: """
    event: message_start
    data: {"type":"message_start","message":{"id":"fixture"}}

    event: ping
    data: {"type":"ping"}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"internal"}}

    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Claude "}}

    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"draft"}}

    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null}}

    data: {"type":"message_stop"}

    """,
    .ollama: """
    {"message":{"role":"assistant","content":"Ollama "},"done":false}
    {"message":{"role":"assistant","content":"draft"},"done":false}
    {"message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}

    """
]

private func title(_ provider: Provider) -> String {
    provider == .anthropic ? "Claude" : provider.title
}

private final class StreamStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let provider = Provider.allCases.first { $0.endpoint.path == url.path }!
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200,
                            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(streamFixtures[provider]!.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class RejectingStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let body = url.path == "/api/chat"
            ? #"{"error":"model 'missing' not found"}"#
            : #"{"type":"error","error":{"type":"authentication_error","message":"invalid\n  x-api-key"}}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: url.path == "/api/chat" ? 404 : 401,
                            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor Partials {
    var values: [String] = []
    func add(_ value: String) { values.append(value) }
}

private func stubbedSession(_ stub: AnyClass) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [stub]
    return URLSession(configuration: config)
}

@Test(arguments: [Provider.openAI, .anthropic, .ollama])
func streamParserCollectsOnlyReplyText(_ provider: Provider) throws {
    var stream = ReplyStream(provider: provider)
    var pieces: [String] = []
    for line in streamFixtures[provider]!.split(separator: "\n", omittingEmptySubsequences: false) {
        if let piece = try stream.consume(String(line)) { pieces.append(piece) }
    }
    #expect(pieces == ["\(title(provider)) ", "draft"])
    #expect(try stream.finish() == "\(title(provider)) draft")
}

@Test func streamParserReportsTruncationCutoffsAndProviderErrors() throws {
    var cutOff = ReplyStream(provider: .openAI)
    _ = try cutOff.consume(#"data: {"type":"response.output_text.delta","delta":"Partial"}"#)
    #expect(throws: GenerationError.incomplete) { try cutOff.finish() }

    var openAI = ReplyStream(provider: .openAI)
    _ = try openAI.consume(#"data: {"type":"response.output_text.delta","delta":"Partial"}"#)
    _ = try openAI.consume(#"data: {"type":"response.incomplete","response":{"status":"incomplete"}}"#)
    #expect(throws: GenerationError.incomplete) { try openAI.finish() }

    var claude = ReplyStream(provider: .anthropic)
    _ = try claude.consume(#"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Partial"}}"#)
    _ = try claude.consume(#"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#)
    _ = try claude.consume(#"data: {"type":"message_stop"}"#)
    #expect(throws: GenerationError.incomplete) { try claude.finish() }

    var ollama = ReplyStream(provider: .ollama)
    _ = try ollama.consume(#"{"message":{"content":"Partial"},"done":true,"done_reason":"length"}"#)
    #expect(throws: GenerationError.incomplete) { try ollama.finish() }

    var empty = ReplyStream(provider: .ollama)
    _ = try empty.consume(#"{"message":{"content":"  "},"done":true,"done_reason":"stop"}"#)
    #expect(throws: GenerationError.emptyReply) { try empty.finish() }

    var overloaded = ReplyStream(provider: .anthropic)
    #expect(throws: GenerationError.provider(nil, "Overloaded")) {
        try overloaded.consume(#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
    }
    var failed = ReplyStream(provider: .openAI)
    #expect(throws: GenerationError.provider(nil, "Quota exceeded")) {
        try failed.consume(#"data: {"type":"response.failed","response":{"error":{"message":"Quota exceeded"}}}"#)
    }
    var local = ReplyStream(provider: .ollama)
    #expect(throws: GenerationError.provider(nil, "out of memory")) {
        try local.consume(#"{"error":"out of memory"}"#)
    }
    #expect(throws: GenerationError.invalidResponse) { try local.consume("not JSON") }
}

@Test(arguments: [Provider.openAI, .anthropic, .ollama])
func streamingRequestDeliversPartialsThenTheFinishedReply(_ provider: Provider) async throws {
    let session = stubbedSession(StreamStub.self)
    defer { session.finishTasksAndInvalidate() }
    let generator = HTTPGenerator(settings: settings(provider), key: "fixture-key", session: session)
    let prompt = ReplyPrompt(source: "How does it work?")

    let request = try generator.request(for: prompt, streaming: true)
    let data = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["stream"] as? Bool == true)

    let partials = Partials()
    let reply = try await generator.stream(prompt) { await partials.add($0) }
    #expect(reply == "\(title(provider)) draft")
    #expect(await partials.values == ["\(title(provider)) ", "\(title(provider)) draft"])
}

@Test(arguments: [Provider.anthropic, .ollama])
func failedRequestsSurfaceTheProvidersOwnMessage(_ provider: Provider) async throws {
    let session = stubbedSession(RejectingStub.self)
    defer { session.finishTasksAndInvalidate() }
    let generator = HTTPGenerator(settings: settings(provider), key: "fixture-key", session: session)
    let prompt = ReplyPrompt(source: "Question")
    let expected: GenerationError = provider == .ollama
        ? .provider(404, "model 'missing' not found") : .provider(401, "invalid x-api-key")

    await #expect(throws: expected) { try await generator.generate(prompt) }
    await #expect(throws: expected) { try await generator.stream(prompt) { _ in } }
    #expect(expected.errorDescription?.hasSuffix("The provider said: \(provider == .ollama ? "model 'missing' not found" : "invalid x-api-key")") == true)
    #expect(HTTPGenerator.failure(status: 500, body: Data("<html>".utf8)) == .http(500))
    #expect(HTTPGenerator.clean(String(repeating: "x", count: 900))?.count == 300)
}

@Test func ollamaModelListKeepsLocalModelsInOrder() throws {
    let data = Data(#"{"models":[{"name":"qwen3:8b","size":1},{"name":"big:cloud"},{"name":"gemma3:4b"}]}"#.utf8)
    #expect(try HTTPGenerator.decodeOllamaModels(data) == ["gemma3:4b", "qwen3:8b"])
    #expect(throws: GenerationError.invalidResponse) { try HTTPGenerator.decodeOllamaModels(Data("{}".utf8)) }
}
