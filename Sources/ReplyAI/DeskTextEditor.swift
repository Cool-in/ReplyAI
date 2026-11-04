import AppKit
import SwiftUI

struct DeskTextEditor: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let font: NSFont
    let textColor: NSColor
    let caretColor: NSColor
    let focusChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = EditorScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false

        let editor = FocusTextView()
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 0, height: 0)
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.setAccessibilityLabel(label)
        editor.delegate = context.coordinator
        let coordinator = context.coordinator
        editor.focusChanged = { [weak coordinator] focused in
            DispatchQueue.main.async { coordinator?.parent.focusChanged(focused) }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        editor.defaultParagraphStyle = paragraph
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        editor.isEditable = enabled
        editor.isSelectable = enabled
        if editor.font != font { editor.font = font }
        if editor.textColor != textColor { editor.textColor = textColor }
        editor.insertionPointColor = caretColor

        if editor.string != text, !editor.hasMarkedText() {
            let selection = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            let start = min(selection.location, length)
            editor.setSelectedRange(NSRange(location: start, length: min(selection.length, length - start)))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DeskTextEditor

        init(parent: DeskTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, !editor.hasMarkedText() else { return }
            if parent.text != editor.string { parent.text = editor.string }
        }
    }
}

private final class FocusTextView: NSTextView {
    var focusChanged: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false) }
        return accepted
    }
}

private final class EditorScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let editor = documentView as? NSTextView else { return }
        let viewport = contentSize
        guard viewport.width > 0, viewport.height > 0 else { return }
        if editor.minSize.height != viewport.height {
            editor.minSize = NSSize(width: 0, height: viewport.height)
        }
        if editor.frame.width != viewport.width || editor.frame.height < viewport.height {
            editor.setFrameSize(NSSize(width: viewport.width, height: max(editor.frame.height, viewport.height)))
        }
    }
}
