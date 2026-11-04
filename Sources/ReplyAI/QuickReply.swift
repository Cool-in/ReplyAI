import AppKit
import SwiftUI

@MainActor
final class QuickReplyController {
    private let model = AppModel.shared
    private var panel: QuickReplyPanel?

    func show(_ capture: SelectionCapture? = nil) {
        model.isOverlayVisible = true
        if case .selected(let text) = capture { model.acceptSelection(text) }
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: QuickReplyView(
            model: model,
            capture: capture,
            close: { [weak self] in self?.hide() },
            openWorkspace: { [weak self] section in self?.openWorkspace(section) },
            resize: { [weak self] confirming in self?.resizePanel(confirming: confirming) }
        ))
        resizePanel(confirming: model.pendingSource != nil)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        model.pendingSource = nil
        model.isOverlayVisible = false
    }

    private func openWorkspace(_ section: Section) {
        hide()
        model.section = section
        model.showWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resizePanel(confirming: Bool) {
        guard let panel else { return }
        let point = NSEvent.mouseLocation
        let screen = panel.isVisible ? panel.screen : NSScreen.screens.first { $0.frame.contains(point) }
        let idealHeight: CGFloat = confirming ? 280 : 520
        guard let frame = (screen ?? NSScreen.main)?.visibleFrame else {
            panel.setContentSize(NSSize(width: 480, height: idealHeight))
            panel.center()
            return
        }
        let width = min(480, frame.width - 28)
        let height = min(idealHeight, frame.height - 28)
        let x = panel.isVisible ? panel.frame.midX - width / 2 : frame.midX - width / 2
        let y = panel.isVisible ? panel.frame.maxY - height : frame.midY - height / 2 + 24
        panel.setFrame(NSRect(
            x: min(max(x, frame.minX + 14), frame.maxX - width - 14),
            y: min(max(y, frame.minY + 14), frame.maxY - height - 14),
            width: width, height: height
        ), display: true)
    }

    private func makePanel() -> QuickReplyPanel {
        let panel = QuickReplyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "ReplyAI Quick Reply"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.onEscape = { [weak self] in self?.hide() }
        self.panel = panel
        return panel
    }
}

private final class QuickReplyPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onEscape?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct QuickReplyView: View {
    @Bindable var model: AppModel
    @State var capture: SelectionCapture?
    let close: () -> Void
    let openWorkspace: (Section) -> Void
    let resize: (Bool) -> Void
    @State private var reviewing = false
    @Environment(\.colorScheme) private var colorScheme

    private var desk: DeskPalette { DeskPalette(dark: colorScheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let pending = model.pendingSource {
                replacement(pending)
            } else if reviewing {
                PromptDetails(model: model) { reviewing = false }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        if let message = capture?.message {
                            captureHint(message)
                        }
                        if model.demo {
                            Label("Fictional example · Simulated draft · No model request", systemImage: "info.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(desk.violet)
                        }
                        source
                        draft
                        if let error = model.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red).font(.callout)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
                footer
            }
        }
        .background(desk.canvas)
        .foregroundStyle(desk.text)
        .tint(desk.violet)
        .environment(\.desk, desk)
        .onChange(of: model.draft) { _, _ in model.copied = false }
        .onChange(of: model.pendingSource != nil) { _, pending in
            reviewing = false
            resize(pending)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            DeskGlyph(symbol: "quote.bubble.fill", size: 29)
            VStack(alignment: .leading, spacing: 1) {
                Text("Quick reply")
                    .font(.system(size: 22, design: .serif))
                    .accessibilityAddTraits(.isHeader)
                Text("ReplyAI").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(desk.railMuted)
            }
            Spacer(minLength: 0)
            Button { openWorkspace(.reply) } label: {
                Label("Open Workspace", systemImage: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 33)
                    .background(desk.railSelection, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 33, height: 33)
                    .background(desk.railSelection, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close Quick Reply")
        }
        .foregroundStyle(desk.railText)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(desk.sidebar)
    }

    private var source: some View {
        Panel(padding: 11) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Comment").font(.system(size: 14, weight: .semibold))
                        if model.importedSource {
                            Text("Imported text").font(.caption).foregroundStyle(desk.muted)
                        }
                    }
                    Spacer()
                    Button("Paste", systemImage: "document.on.clipboard") {
                        capture = nil
                        model.pasteSource()
                    }
                    .buttonStyle(DeskButton())
                }
                WritingField(text: $model.source, placeholder: "Paste or type the comment you want to answer…",
                             label: "Comment", height: 42, onPaper: true)
                Rectangle().fill(desk.line).frame(height: 1)
                TextField("Reply brief, optional", text: $model.brief)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .accessibilityLabel("Reply brief")
                DraftOptions(model: model)
            }
            .disabled(model.isGenerating || model.pendingSource != nil)
        }
    }

    private var draft: some View {
        Panel(padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your draft").font(.system(size: 14, weight: .semibold))
                    if model.draftIsDemo {
                        Text("Simulated").font(.caption.weight(.semibold)).foregroundStyle(desk.violet)
                    }
                    Spacer()
                    Button(model.copied ? "Copied" : "Copy Draft", systemImage: model.copied ? "checkmark" : "doc.on.doc") {
                        model.copyDraft()
                    }
                    .buttonStyle(DeskButton())
                    .disabled(!model.hasDraft)
                }
                WritingField(text: $model.draft, placeholder: "Your reply will appear here. You can also start writing.",
                             label: "Editable draft", height: 87, onPaper: true)
            }
            .disabled(model.pendingSource != nil)
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.generationDestination).font(.system(size: 12, weight: .semibold))
                Text(model.generationContext).font(.system(size: 11)).foregroundStyle(desk.muted)
            }
            Spacer(minLength: 0)
            Button("Review Input", systemImage: "eye") { reviewing = true }
                .buttonStyle(DeskButton())
                .disabled(!model.hasSource)
            GenerateReplyControl(model: model) { openWorkspace(.settings) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(desk.paper)
        .disabled(model.pendingSource != nil)
    }

    private func captureHint(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "cursorarrow")
                .font(.system(size: 12))
                .foregroundStyle(desk.text)
                .fixedSize(horizontal: false, vertical: true)
            if capture == .needsPermission {
                Button("Enable Selection Access") { SelectionCapture.requestAccess() }
                    .buttonStyle(DeskButton())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(desk.wash, in: RoundedRectangle(cornerRadius: 9))
    }

    private func replacement(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("New selection").foregroundStyle(desk.violet).accessibilityHidden(true)
            Text("Replace this reply?")
                .font(.system(size: 25, design: .serif))
                .accessibilityAddTraits(.isHeader)
            Text("Keep your current draft or start a reply to this selection.")
                .font(.system(size: 13))
                .foregroundStyle(desk.muted)
            Text(text)
                .font(.system(size: 13))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(desk.paper, in: RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Spacer()
                Button("Keep Current") { model.pendingSource = nil }.buttonStyle(DeskButton())
                Button("Replace") {
                    model.replaceSource(text)
                    capture = nil
                }
                .buttonStyle(DeskButton(kind: .primary))
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
