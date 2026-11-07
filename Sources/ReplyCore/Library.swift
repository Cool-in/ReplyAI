import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI, anthropic, ollama

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .ollama: "Ollama"
        }
    }

    public var exampleModel: String {
        switch self {
        case .openAI: "gpt-4.1-mini"
        case .anthropic: "claude-sonnet-5-5"
        case .ollama: "gemma3:4b"
        }
    }

    public var endpoint: URL {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/responses")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")!
        case .ollama: URL(string: "http://127.0.0.1:11434/api/chat")!
        }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var provider: Provider = .ollama
    public var models: [String: String] = [:]
    public var model: String {
        get { models[provider.rawValue] ?? "" }
        set { models[provider.rawValue] = newValue }
    }

    public init() {}
}

public struct VoiceSample: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var text: String

    public init(text: String) { self.text = text }
}

public struct ProjectDocument: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var text: String
    public var importedAt = Date()

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var documents: [ProjectDocument] = []

    public init(name: String) { self.name = name }
}

public struct Library: Codable, Equatable, Sendable {
    public var settings = Settings()
    public var voiceNotes = ""
    public var samples: [VoiceSample] = []
    public var projects: [Project] = []

    public init() {}
}

public struct LibraryStore: Sendable {
    public var file: URL

    public init(file: URL) { self.file = file }

    public func load() throws -> Library {
        do {
            return try JSONDecoder().decode(Library.self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Library()
        }
    }

    public func save(_ library: Library) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(library).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
