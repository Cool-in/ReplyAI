import SwiftUI

struct HelpView: View {
    let model: AppModel
    let openQuickReply: () -> Void
    @Environment(\.desk) private var desk

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(kicker: "Getting started", title: "How to use ReplyAI",
                      subtitle: "From highlighted text to a draft you can make your own.")

            Panel {
                VStack(alignment: .leading, spacing: 19) {
                    step("01", title: "Set up your writing desk") {
                        Text("Choose a model in Settings. Add a few posts or messages you wrote in My voice. If a reply needs product facts, add the relevant files in Projects.")
                        HStack(spacing: 8) {
                            Button("Settings", systemImage: "gearshape") { model.section = .settings }
                                .buttonStyle(DeskButton())
                            Button("My voice", systemImage: "waveform") { model.section = .voice }
                                .buttonStyle(DeskButton())
                        }
                    }
                    rule
                    step("02", title: "Highlight the comment") {
                        Text("With ReplyAI running, select the text in the other app. Choose Services → Draft Reply with ReplyAI to open Quick Reply.")
                        HStack(spacing: 9) {
                            Text(model.library.settings.shortcut.title).font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(desk.violet)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(desk.wash, in: RoundedRectangle(cornerRadius: 6))
                                .accessibilityLabel(model.library.settings.shortcut.spoken)
                            Text("Global shortcut").font(.system(size: 12, weight: .semibold))
                        }
                        if let status = model.shortcutRegistrationStatus, status != 0 {
                            Label("This shortcut couldn’t register on this Mac. Choose another in Settings, or use Services or Paste.", systemImage: "exclamationmark.circle")
                        } else {
                            Text("Shortcut capture needs Accessibility access. If asked, choose Enable Selection Access and retry from the other app.")
                        }
                        Text("You can also copy the comment, open Quick Reply, and click Paste.")
                        Button("Open Quick Reply", systemImage: "quote.bubble", action: openQuickReply)
                            .buttonStyle(DeskButton())
                    }
                    rule
                    step("03", title: "Generate, edit, and copy") {
                        Text("Choose a project and length if you like. Review Input shows what the model will receive. Click Generate Reply, edit the draft, then click Copy Draft and paste it where you’re replying.")
                        Text("Press Esc to hide Quick Reply and keep your draft. Open Workspace takes you back to the full app.")
                    }
                }
            }
        }
        .frame(maxWidth: 695, alignment: .leading)
    }

    private var rule: some View {
        Rectangle().fill(desk.line).frame(height: 1)
    }

    private func step<Content: View>(_ number: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Eyebrow(number)
                .foregroundStyle(desk.violet)
                .frame(width: 32, height: 32)
                .background(desk.wash, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 22, design: .serif)).foregroundStyle(desk.text)
                    .accessibilityAddTraits(.isHeader)
                content()
                    .font(.system(size: 13))
                    .foregroundStyle(desk.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
