import AppKit
import Observation
import os
import ReplyCore

enum Section: String, CaseIterable, Identifiable {
    case reply = "Reply", voice = "My voice", projects = "Projects", settings = "Settings", help = "How to Use"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .reply: "bubble.left.and.bubble.right"
        case .voice: "waveform"
        case .projects: "folder"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        }
    }
}

/// Non-content diagnostics only: never comment text, drafts, prompts or keys.
let appLog = Logger(subsystem: "dev.replyai.mac", category: "app")

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    var library = Library()
    var section: Section? = .reply
    var source = ""
    var brief = ""
    /// The draft and its generation state. The logic lives in ReplyCore, where it is tested.
    var draftState = DraftState()
    var errorMessage: String?
    var storageError: String?
    var copied = false
    var pendingSource: String?
    var keySaved = false
    var importedSource = false
    var showWindow: (() -> Void)?
    var isOverlayVisible = false
    var shortcutRegistrationStatus: Int32?
    /// Set by the app delegate. Re-registers the global shortcut and returns the registration status.
    var applyShortcut: ((ShortcutPreset) -> Int32)?
    private var exampleLoaded = false
    private var request: Task<Void, Never>?
    private var pendingSave: Task<Void, Never>?
    private var dirty = false
    private let store: LibraryStore?
    private var canSave = true

    init() {
        if ProcessInfo.processInfo.arguments.contains("--temporary-library") {
            store = nil
        } else {
            store = LibraryStore(file: URL.applicationSupportDirectory
                .appending(path: "ReplyAI", directoryHint: .isDirectory)
                .appending(path: "Library.json"))
        }
        do {
            if let store { library = try store.load() }
        } catch LibraryStore.Failure.newerVersion {
            canSave = false
            storageError = "This library was saved by a newer version of ReplyAI. Update the app to use it. Changes made now are temporary."
            appLog.error("Library was written by a newer version; running without saving.")
        } catch {
            canSave = false
            storageError = "The saved library could not be read. Changes are temporary until you recover or move Library.json."
            appLog.error("Library could not be read; running without saving.")
        }
        checkKey()
    }

    var draft: String {
        get { draftState.text }
        set { draftState.text = newValue }
    }
    var draftIsDemo: Bool { draftState.isDemo }
    /// The draft that the last generation replaced, kept so it can be brought back.
    var previousDraft: String? { draftState.previous }
    var isGenerating: Bool { draftState.isGenerating }

    /// Length and project are remembered between launches.
    var length: ReplyLength {
        get { library.settings.length }
        set { library.settings.length = newValue }
    }
    var selectedProjectID: UUID? {
        get { library.settings.selectedProjectID }
        set { library.settings.selectedProjectID = newValue }
    }

    /// Example mode lasts only while the example comment is untouched.
    var demo: Bool { exampleLoaded && source == Self.demoSource }

    var hasSource: Bool { !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasDraft: Bool { draftState.hasText }
    var project: Project? { library.projects.first { $0.id == selectedProjectID } }
    var libraryFile: URL? { store?.file }

    var hasConfiguredModel: Bool {
        !library.settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (library.settings.provider == .ollama || keySaved)
    }

    var generationDestination: String {
        if demo { return "On this Mac · Demo" }
        let provider = library.settings.provider
        return provider == .ollama ? "Ollama on this Mac" : provider.title
    }

    var generationContext: String {
        let counts = ReplyPrompt.contextCounts(
            samples: demo ? Self.demoSamples : library.samples,
            project: demo ? Self.demoProject : project
        )
        return "\(counts.samples) \(counts.samples == 1 ? "sample" : "samples") · \(counts.documents) \(counts.documents == 1 ? "excerpt" : "excerpts")"
    }

    var prompt: ReplyPrompt {
        ReplyPrompt(
            source: source, brief: brief,
            voiceNotes: demo ? "" : library.voiceNotes,
            samples: demo ? Self.demoSamples : library.samples,
            project: demo ? Self.demoProject : project, length: length
        )
    }

    /// Queues a save. Rapid edits collapse into one write shortly after typing stops.
    func save() {
        guard canSave, store != nil else { return }
        dirty = true
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    /// Writes any queued changes right away. Called on quit so nothing is lost.
    func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard dirty, canSave, let store else { return }
        dirty = false
        do {
            try store.save(library)
            storageError = nil
        } catch {
            storageError = "Could not save your library. Check the app’s Application Support folder."
            appLog.error("Library save failed.")
        }
    }

    func revealLibrary() {
        guard let libraryFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([libraryFile])
    }

    func checkKey() {
        let provider = library.settings.provider
        keySaved = provider != .ollama && Keychain.exists(provider)
    }

    func pasteSource() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            errorMessage = "The clipboard doesn’t contain text."
            return
        }
        acceptSelection(text)
    }

    func acceptSelection(_ text: String) {
        section = .reply
        if text == source {
            pendingSource = nil
            return
        }
        if hasSource || hasDraft || isGenerating {
            pendingSource = text
        } else {
            replaceSource(text)
        }
    }

    /// Text captured from another app. Starts drafting straight away when the user has opted in
    /// and nothing needs confirming first.
    func acceptCapture(_ text: String) {
        let fresh = text != source
        acceptSelection(text)
        if fresh, library.settings.generateOnCapture, pendingSource == nil, source == text, hasConfiguredModel {
            generate()
        }
    }

    func replaceSource(_ text: String) {
        cancel()
        exampleLoaded = false
        source = text
        brief = ""
        draftState.reset()
        copied = false
        errorMessage = nil
        pendingSource = nil
        importedSource = true
    }

    func loadDemo() {
        cancel()
        exampleLoaded = true
        importedSource = false
        source = Self.demoSource
        brief = "Reassure them and explain what happens when they reconnect."
        draftState.reset()
        errorMessage = nil
        copied = false
        section = .reply
    }

    func clear() {
        replaceSource("")
        importedSource = false
    }

    func generate() {
        guard hasSource, !isGenerating else { return }
        guard source.count <= ReplyPrompt.maxSource, brief.count <= ReplyPrompt.maxNotes else {
            errorMessage = "Shorten the comment or reply brief before generating."
            return
        }
        let prompt = prompt
        let settings = library.settings
        let isDemo = demo
        let token = draftState.begin()
        errorMessage = nil
        copied = false
        request = Task {
            do {
                let output: String
                if isDemo {
                    try await Task.sleep(for: .milliseconds(320))
                    output = Self.demoReply
                } else {
                    let key = settings.provider == .ollama ? nil : try Keychain.read(settings.provider)
                    output = try await HTTPGenerator(settings: settings, key: key).stream(prompt) { [weak self] text in
                        await self?.showPartial(text, token: token)
                    }
                }
                try Task.checkCancellation()
                if draftState.finish(output, isDemo: isDemo, token: token) {
                    announce("Draft ready.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                let applied: Bool
                if let failure = error as? GenerationError, case .cutShort(let partial) = failure {
                    // Keep what arrived. The earlier draft stays available as Previous Draft.
                    applied = draftState.finish(partial, token: token)
                } else {
                    applied = draftState.fail(token: token)
                }
                guard applied else { return }
                let message: String
                if let error = error as? URLError {
                    message = error.code == .timedOut ? "The request timed out. Try again or choose a faster model."
                        : "Could not reach \(settings.provider.title). Check your connection or make sure Ollama is running."
                } else {
                    message = error.localizedDescription
                }
                errorMessage = message
                announce(message)
                appLog.error("Generation failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    func cancel() {
        request?.cancel()
        request = nil
        draftState.cancel()
    }

    /// Shows the reply as it streams in. Late updates from a cancelled request are ignored.
    private func showPartial(_ text: String, token: Int) {
        draftState.showPartial(text, token: token)
    }

    /// Swaps the current draft with the one the last generation replaced.
    func restorePreviousDraft() {
        draftState.swapPrevious()
    }

    func copyDraft() {
        guard hasDraft else { return }
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(draft, forType: .string)
        if !copied { errorMessage = "Could not copy the draft to the clipboard." }
    }

    /// Speaks a short status for VoiceOver users, who otherwise get no signal that a draft finished or failed.
    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    static let demoSource = "Does Trailnote keep working if I lose signal out on the trail?"
    static let demoReply = "Yep! Trailnote keeps your notes on your Mac while you’re offline. They’ll sync when you’re back online, so you can keep writing even if you lose signal."

    static let demoSamples = [
        VoiceSample(text: "Yep! You can start with the basics and tweak it as you go."),
        VoiceSample(text: "Happy to help. The quickest way is to save your route first, then start a new note.")
    ]

    static var demoProject: Project {
        var project = Project(name: "Trailnote")
        project.documents = [.init(name: "About Trailnote.txt", text: "Trailnote is a fictional Mac hiking journal. Notes are saved locally when offline and sync when internet access returns.")]
        return project
    }
}
