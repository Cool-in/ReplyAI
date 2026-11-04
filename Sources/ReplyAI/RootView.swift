import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    let openQuickReply: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    private var desk: DeskPalette { DeskPalette(dark: colorScheme == .dark) }

    var body: some View {
        GeometryReader { geometry in
            let rail: CGFloat = geometry.size.width >= 960 ? 205 : 171
            let margin: CGFloat = geometry.size.width >= 960 ? 38 : 26
            let contentWidth = geometry.size.width - rail - margin * 2
            HStack(spacing: 0) {
                DeskRail(selection: $model.section)
                    .frame(width: rail)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = model.storageError {
                            Label(error, systemImage: "externaldrive.badge.exclamationmark")
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                        switch model.section ?? .reply {
                        case .reply: ComposerView(model: model, wide: contentWidth >= 670)
                        case .voice: VoiceView(model: model)
                        case .projects: ProjectsView(model: model)
                        case .settings: ProviderView(model: model)
                        case .help: HelpView(model: model, openQuickReply: openQuickReply)
                        }
                    }
                    .frame(maxWidth: model.section == .reply ? 1060 : 780, alignment: .leading)
                    .padding(.horizontal, margin)
                    .padding(.top, 52)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
                .background(desk.canvas)
            }
        }
        .background(desk.canvas)
        .foregroundStyle(desk.text)
        .tint(desk.violet)
        .environment(\.desk, desk)
        .onAppear {
            model.showWindow = { openWindow(id: "composer") }
        }
        .onChange(of: model.library) { _, _ in model.save() }
        .alert("Replace this reply?", isPresented: Binding(
            get: { !model.isOverlayVisible && model.pendingSource != nil },
            set: { if !$0 && !model.isOverlayVisible { model.pendingSource = nil } }
        )) {
            Button("Keep Current", role: .cancel) { model.pendingSource = nil }
            Button("Replace", role: .destructive) {
                if let text = model.pendingSource { model.replaceSource(text) }
            }
        } message: {
            Text("The new selection will replace the comment, brief, and current draft.")
        }
    }
}

private struct DeskRail: View {
    @Binding var selection: Section?
    @Environment(\.desk) private var desk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(desk.sidebar)
                    .frame(width: 34, height: 34)
                    .background(desk.railAccent, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                Text("ReplyAI")
                    .font(.system(size: 23, weight: .regular, design: .serif))
                    .tracking(-0.7)
                    .foregroundStyle(desk.railText)
            }
            .padding(.horizontal, 4)

            Eyebrow("Workspace")
                .foregroundStyle(desk.railMuted)
                .padding(.leading, 9)
                .padding(.top, 42)
                .padding(.bottom, 12)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                ForEach(Section.allCases.filter { $0 != .help }) { section in
                    RailLink(section: section, selected: (selection ?? .reply) == section) {
                        selection = section
                    }
                }
            }

            Spacer()
            RailLink(section: .help, selected: selection == .help) { selection = .help }
                .padding(.bottom, 12)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 13))
                    .foregroundStyle(desk.railAccent)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Library on this Mac")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(desk.railText)
                    Text("You decide what to send.")
                        .font(.system(size: 11))
                        .foregroundStyle(desk.railMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(desk.railMuted.opacity(0.20)).frame(height: 1) }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 57)
        .padding(.bottom, 25)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(desk.sidebar)
    }
}

private struct RailLink: View {
    let section: Section
    let selected: Bool
    let activate: () -> Void
    @Environment(\.desk) private var desk
    @State private var hover = false

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? desk.railAccent : desk.railMuted)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer()
                if selected {
                    Circle().fill(desk.railAccent).frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 39)
            .foregroundStyle(selected ? desk.railText : desk.railMuted)
            .background(
                selected ? desk.railSelection : hover ? desk.railSelection.opacity(0.52) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
