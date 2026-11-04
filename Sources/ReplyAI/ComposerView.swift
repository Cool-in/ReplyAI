import SwiftUI
import ReplyCore

struct ComposerView: View {
    @Bindable var model: AppModel
    let wide: Bool
    @State private var preview = false
    @State private var confirmDemo = false
    @Environment(\.desk) private var desk

    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack(alignment: .center, spacing: 12) {
                PageTitle(kicker: "Writing desk", title: "Write a reply", subtitle: "Start with a comment. Make the reply sound like you.")
                Button("Try Example", systemImage: "sparkles") {
                    if model.hasSource || model.hasDraft { confirmDemo = true } else { model.loadDemo() }
                }
                .buttonStyle(DeskButton())
                .fixedSize()
            }
            .padding(.bottom, 5)

            if model.demo {
                Label("Fictional example · Simulated draft · No model request", systemImage: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(desk.violet)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(desk.wash, in: RoundedRectangle(cornerRadius: 8))
            }

            if wide {
                GeometryReader { geometry in
                    HStack(alignment: .top, spacing: 16) {
                        sourceSheet.frame(width: (geometry.size.width - 16) * 0.44)
                        draftSheet
                    }
                }
                .frame(height: 407)
                actionRow
            } else {
                sourceSheet
                actionRow
                draftSheet
            }

            if !model.hasSource && !model.demo {
                Label("In another Mac app, select text and choose Services → Draft Reply with ReplyAI.", systemImage: "cursorarrow")
                    .font(.system(size: 11))
                    .foregroundStyle(desk.muted)
                    .padding(.top, 1)
            }
        }
        .onChange(of: model.draft) { _, _ in model.copied = false }
        .sheet(isPresented: $preview) { PromptPreview(model: model) }
        .confirmationDialog("Replace this reply with an example?", isPresented: $confirmDemo) {
            Button("Load Example", role: .destructive) { model.loadDemo() }
        } message: {
            Text("The example replaces your current comment, brief, and draft.")
        }
    }

    private var sourceSheet: some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    DeskGlyph(symbol: "text.quote")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Comment").font(.system(size: 16, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(model.importedSource ? "Imported text" : "Source text")
                            .font(.system(size: 11))
                            .foregroundStyle(desk.muted)
                    }
                    Spacer(minLength: 0)
                    Button("Paste", systemImage: "document.on.clipboard") { model.pasteSource() }
                        .buttonStyle(DeskButton())
                }

                WritingField(
                    text: $model.source, placeholder: "Paste a post, comment, or message to answer…",
                    label: "Comment", height: 113, onPaper: true
                )
                Rectangle().fill(desk.line).frame(height: 1)

                HStack(spacing: 6) {
                    Text("Reply brief").font(.system(size: 12, weight: .semibold))
                    Text("Optional").font(.system(size: 11)).foregroundStyle(desk.muted)
                }
                WritingField(text: $model.brief, placeholder: "What should your reply say?",
                             label: "Reply brief", height: 43, onPaper: true)

                if model.source.count > ReplyPrompt.maxSource || model.brief.count > ReplyPrompt.maxNotes {
                    Text("Limit: 6,000 characters for the comment and 1,000 for the brief.")
                        .font(.caption).foregroundStyle(.red)
                }

                Spacer(minLength: 0)
                DraftOptions(model: model)
            }
            .frame(minHeight: wide ? 363 : 327, maxHeight: wide ? 363 : nil, alignment: .topLeading)
            .disabled(model.isGenerating)
        }
    }

    private var draftSheet: some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    DeskGlyph(symbol: "pencil.line")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your draft").font(.system(size: 16, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Edit before you copy")
                            .font(.system(size: 11))
                            .foregroundStyle(desk.muted)
                    }
                    Spacer(minLength: 0)
                    if model.draftIsDemo {
                        Text("Simulated")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(desk.violet)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(desk.wash, in: Capsule())
                    }
                }

                ZStack {
                    WritingField(text: $model.draft, placeholder: "", label: "Editable draft",
                                 height: wide ? 242 : 176, onPaper: true)
                    if model.draft.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: "quote.closing")
                                .font(.system(size: 25, weight: .light))
                                .foregroundStyle(desk.violet)
                                .symbolEffect(.pulse, isActive: model.isGenerating)
                                .padding(.bottom, 2)
                            Text(model.isGenerating ? "Writing your reply…" : "Room for your reply")
                                .font(.system(size: 25, design: .serif))
                                .foregroundStyle(desk.text)
                            Text("Generate a draft or start writing here.")
                                .font(.system(size: 12))
                                .foregroundStyle(desk.muted)
                        }
                        .padding(12)
                        .multilineTextAlignment(.center)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 0)
                Rectangle().fill(desk.line).frame(height: 1)
                HStack(spacing: 7) {
                    Text(model.hasDraft ? "\(model.draft.count) characters" : "Nothing is posted.")
                        .font(.system(size: 11))
                        .foregroundStyle(desk.muted)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if model.hasSource || model.hasDraft {
                        Button("Clear") { model.clear() }
                            .buttonStyle(DeskButton(kind: .quiet))
                    }
                    Button(model.copied ? "Copied" : "Copy Draft", systemImage: model.copied ? "checkmark" : "doc.on.doc") {
                        model.copyDraft()
                    }
                    .buttonStyle(DeskButton())
                    .disabled(!model.hasDraft)
                }
            }
            .frame(minHeight: wide ? 363 : 290, maxHeight: wide ? 363 : nil, alignment: .topLeading)
        }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.generationDestination)
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.generationContext)
                        .font(.system(size: 11))
                        .foregroundStyle(desk.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Review Input", systemImage: "eye") { preview = true }
                    .buttonStyle(DeskButton())
                    .disabled(!model.hasSource)
                GenerateReplyControl(model: model) { model.section = .settings }
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

}

struct DraftOptions: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            if model.demo {
                MenuChip(title: "Trailnote", symbol: "folder")
            } else {
                Menu {
                    Picker("Project", selection: $model.selectedProjectID) {
                        Text("No project").tag(nil as UUID?)
                        ForEach(model.library.projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    MenuChip(title: model.project?.name ?? "No project", symbol: "folder", showsArrow: true)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Project")
                .accessibilityValue(model.project?.name ?? "No project")
            }
            Menu {
                Picker("Length", selection: $model.length) {
                    ForEach(ReplyLength.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                MenuChip(title: model.length.rawValue, symbol: "text.alignleft", showsArrow: true)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Length")
            .accessibilityValue(model.length.rawValue)
            Spacer(minLength: 0)
        }
    }

}

struct GenerateReplyControl: View {
    let model: AppModel
    let openSettings: () -> Void

    var body: some View {
        if model.isGenerating {
            ProgressView().controlSize(.small).accessibilityLabel("Generating draft")
            Button("Cancel") { model.cancel() }
                .buttonStyle(DeskButton())
        } else if model.hasConfiguredModel || model.demo {
            Button("Generate Reply", systemImage: "sparkles") { model.generate() }
                .buttonStyle(DeskButton(kind: .primary))
                .disabled(!model.hasSource)
        } else {
            Button("Set Up a Model", systemImage: "arrow.up.right", action: openSettings)
                .buttonStyle(DeskButton(kind: .primary))
        }
    }

}

private struct MenuChip: View {
    let title: String
    let symbol: String
    var showsArrow = false
    @Environment(\.desk) private var desk

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(desk.violet)
            Text(title).lineLimit(1)
            if showsArrow {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(desk.muted)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(desk.text)
        .padding(.horizontal, 9)
        .frame(minHeight: 32)
        .background(desk.inset, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PromptPreview: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PromptDetails(model: model) { dismiss() }
            .frame(width: 640, height: 540)
    }
}

struct PromptDetails: View {
    let model: AppModel
    let done: () -> Void
    @Environment(\.desk) private var desk

    var body: some View {
        let prompt = model.prompt
        VStack(alignment: .leading, spacing: 13) {
            SheetHeader(kicker: "Draft setup", title: "Review input")
            Text(model.demo
                 ? "This fictional input illustrates what a model would receive. Demo mode makes no request."
                 : "When you click Generate Reply, this input and the instructions below go to \(model.library.settings.provider.title).")
                .font(.callout)
                .foregroundStyle(desk.muted)
            Text("The preview shows the exact excerpts included. Each file contributes at most 2,500 characters.")
                .font(.caption).foregroundStyle(desk.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow("Input").foregroundStyle(desk.violet)
                    Text(prompt.input).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Rectangle().fill(desk.line).frame(height: 1)
                    Eyebrow("Instructions").foregroundStyle(desk.violet)
                    Text(prompt.instructions).font(.callout).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(desk.paper, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Spacer()
                Button("Done", action: done)
                    .buttonStyle(DeskButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .background(desk.canvas)
    }
}
