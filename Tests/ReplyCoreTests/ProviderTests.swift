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
