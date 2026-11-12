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

public enum EditorTextSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small = "Small", standard = "Default", large = "Large", larger = "Larger"

    public var id: String { rawValue }

    public var scale: Double {
        switch self {
        case .small: 0.9
        case .standard: 1
        case .large: 1.15
        case .larger: 1.3
        }
    }
}

/// The global shortcuts ReplyAI can register for capturing a selection.
public enum ShortcutPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case optionShiftR, controlOptionR, controlOptionSpace

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .optionShiftR: "⌥⇧R"
        case .controlOptionR: "⌃⌥R"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }

    public var spoken: String {
        switch self {
        case .optionShiftR: "Option Shift R"
        case .controlOptionR: "Control Option R"
        case .controlOptionSpace: "Control Option Space"
        }
    }
}

// Every type below decodes leniently: a field that is missing from an older file takes its default
// instead of failing the whole load. Add new fields the same way.

public struct Settings: Codable, Equatable, Sendable {
    public var provider: Provider = .ollama
    public var models: [String: String] = [:]
    public var length: ReplyLength = .short
    public var selectedProjectID: UUID?
    public var generateOnCapture = false
    public var textSize: EditorTextSize = .standard
    public var shortcut: ShortcutPreset = .optionShiftR
    public var model: String {
        get { models[provider.rawValue] ?? "" }
        set { models[provider.rawValue] = newValue }
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // A value this version does not recognise falls back to the default rather than failing.
        provider = (try? values.decodeIfPresent(Provider.self, forKey: .provider)) ?? .ollama
        models = try values.decodeIfPresent([String: String].self, forKey: .models) ?? [:]
        length = (try? values.decodeIfPresent(ReplyLength.self, forKey: .length)) ?? .short
        selectedProjectID = try? values.decodeIfPresent(UUID.self, forKey: .selectedProjectID)
        generateOnCapture = (try? values.decodeIfPresent(Bool.self, forKey: .generateOnCapture)) ?? false
        textSize = (try? values.decodeIfPresent(EditorTextSize.self, forKey: .textSize)) ?? .standard
        shortcut = (try? values.decodeIfPresent(ShortcutPreset.self, forKey: .shortcut)) ?? .optionShiftR
    }
}

public struct VoiceSample: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var text: String

    public init(text: String) { self.text = text }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try values.decode(String.self, forKey: .text)
    }
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

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        text = try values.decode(String.self, forKey: .text)
        importedAt = try values.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
    }
}

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var documents: [ProjectDocument] = []

    public init(name: String) { self.name = name }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        documents = try values.decodeIfPresent([ProjectDocument].self, forKey: .documents) ?? []
    }
}

public struct Library: Codable, Equatable, Sendable {
    /// Raise this when a change would make an older app misread the file.
    public static let currentSchema = 2

    public var schemaVersion = Library.currentSchema
    public var settings = Settings()
    public var voiceNotes = ""
    public var samples: [VoiceSample] = []
    public var projects: [Project] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= Self.currentSchema else { throw LibraryStore.Failure.newerVersion(version) }
        settings = try values.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        voiceNotes = try values.decodeIfPresent(String.self, forKey: .voiceNotes) ?? ""
        samples = try values.decodeIfPresent([VoiceSample].self, forKey: .samples) ?? []
        projects = try values.decodeIfPresent([Project].self, forKey: .projects) ?? []
    }
}

public struct LibraryStore: Sendable {
    public var file: URL

    public enum Failure: Error, Equatable {
        /// The file was written by a newer ReplyAI. It is left untouched.
        case newerVersion(Int)
    }

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
