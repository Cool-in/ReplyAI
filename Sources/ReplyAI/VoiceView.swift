import SwiftUI
import ReplyCore

struct VoiceView: View {
    @Bindable var model: AppModel
    @State private var editor: VoiceSample?
    @State private var removing: VoiceSample?
    @Environment(\.desk) private var desk

    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            PageTitle(kicker: "Your library", title: "My voice", subtitle: "Give ReplyAI a few examples of how you actually write.")
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        DeskGlyph(symbol: "slider.horizontal.3")
                        Text("Writing preferences").font(.system(size: 16, weight: .semibold))
                    }
                    WritingField(text: $model.library.voiceNotes,
                                 placeholder: "For example: Keep it plainspoken. Ask one question at a time.",
                                 label: "Writing preferences", height: 70)
                    Text("The first 1,000 characters are included with a reply.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Writing samples").font(.system(size: 25, design: .serif))
                Text("\(model.library.samples.count)").font(.caption.monospacedDigit())
                    .foregroundStyle(desk.violet).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(desk.wash, in: Capsule())
                Spacer()
                Button("Add Sample", systemImage: "plus") { editor = VoiceSample(text: "") }
                    .buttonStyle(DeskButton(kind: .primary))
            }
            Text("Start with 5 to 15 posts or messages you wrote. ReplyAI uses up to 8 of the most recently added samples per draft.")
                .font(.callout).foregroundStyle(.secondary)
            if model.library.samples.isEmpty {
                Panel {
                    DeskEmptyState(icon: "waveform", title: "No samples yet",
                                   text: "Pick short examples that sound like you. Remove names and anything private before saving.")
                }
            } else {
                Panel {
                    VStack(spacing: 0) {
                        ForEach(model.library.samples) { sample in
                            if sample.id != model.library.samples.first?.id {
                                Rectangle().fill(desk.line).frame(height: 1)
                            }
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: "quote.opening").foregroundStyle(desk.violet)
                                    .padding(.top, 4).accessibilityHidden(true)
                                Text(sample.text).font(.system(size: 16, design: .serif))
                                    .lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                                Button("Edit") { editor = sample }.buttonStyle(DeskButton())
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    removing = sample
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(DeskButton(kind: .quiet))
                                .help("Remove sample")
                            }
                            .padding(.vertical, 9)
                        }
                    }
                }
            }
        }
        .confirmationDialog("Remove this writing sample?", isPresented: Binding(
            get: { removing != nil },
            set: { if !$0 { removing = nil } }
        ), presenting: removing) { sample in
            Button("Remove Sample", role: .destructive) {
                model.library.samples.removeAll { $0.id == sample.id }
            }
        } message: { _ in
            Text("This can’t be undone.")
        }
        .sheet(item: $editor) { sample in
            SampleEditor(sample: sample) { value in
                if let index = model.library.samples.firstIndex(where: { $0.id == value.id }) {
                    model.library.samples[index] = value
                } else {
                    model.library.samples.insert(value, at: 0)
                }
            }
        }
    }
}

private struct SampleEditor: View {
    @State var sample: VoiceSample
    let save: (VoiceSample) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.desk) private var desk

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(kicker: "My voice", title: "Writing sample")
            WritingField(text: $sample.text, placeholder: "Paste a short post or reply you wrote…",
                         label: "Writing sample", height: 145)
            HStack {
                Text("\(sample.text.count) / \(ReplyPrompt.maxSample)").monospacedDigit()
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(DeskButton()).keyboardShortcut(.cancelAction)
                Button("Save Sample") {
                    sample.text = sample.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(sample)
                    dismiss()
                }
                .buttonStyle(DeskButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(sample.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || sample.text.count > ReplyPrompt.maxSample)
            }
        }
        .padding(26)
        .frame(width: 540)
        .background(desk.canvas)
    }
}
