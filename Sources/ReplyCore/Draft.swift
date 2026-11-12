import Foundation

/// The draft and what happens to it across a generation: streaming, success, failure, cancel,
/// and swapping back to the draft a generation replaced. Pure state, so it can be tested directly.
public struct DraftState: Equatable, Sendable {
    public var text = ""
    public var isDemo = false
    /// The draft that the last successful generation replaced.
    public private(set) var previous: String?
    public private(set) var isGenerating = false
    private var generation = 0
    private var savedText: String?
    private var savedIsDemo = false

    public init() {}

    public var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Starts a generation and returns its token. Later calls must present the same token.
    public mutating func begin() -> Int {
        generation += 1
        savedText = text
        savedIsDemo = isDemo
        isGenerating = true
        return generation
    }

    /// Shows text as it streams in. Updates from a finished or cancelled generation are ignored.
    public mutating func showPartial(_ partial: String, token: Int) {
        guard token == generation, isGenerating else { return }
        text = partial
        isDemo = false
    }

    /// Accepts the finished reply and remembers the draft it replaced. Returns false for a stale token.
    @discardableResult
    public mutating func finish(_ output: String, isDemo demo: Bool = false, token: Int) -> Bool {
        guard token == generation, isGenerating else { return false }
        let before = savedText ?? ""
        let replaced = before.trimmingCharacters(in: .whitespacesAndNewlines)
        previous = replaced.isEmpty || replaced == output ? nil : before
        text = output
        isDemo = demo
        savedText = nil
        isGenerating = false
        return true
    }

    /// A failed generation puts back the draft that was there before. Returns false for a stale token.
    @discardableResult
    public mutating func fail(token: Int) -> Bool {
        guard token == generation, isGenerating else { return false }
        restore()
        return true
    }

    /// Cancels any generation in flight and puts back the earlier draft. Safe to call when idle.
    public mutating func cancel() {
        generation += 1
        restore()
    }

    /// Swaps the current draft with the one the last generation replaced.
    public mutating func swapPrevious() {
        guard let earlier = previous, !isGenerating else { return }
        previous = hasText ? text : nil
        text = earlier
        isDemo = false
    }

    /// Clears everything, cancelling any generation in flight.
    public mutating func reset() {
        cancel()
        text = ""
        isDemo = false
        previous = nil
    }

    private mutating func restore() {
        if let savedText {
            text = savedText
            isDemo = savedIsDemo
        }
        savedText = nil
        isGenerating = false
    }
}
