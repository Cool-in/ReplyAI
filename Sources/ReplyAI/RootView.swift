import AppKit
import ReplyCore
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    let openQuickReply: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    private var desk: DeskPalette { DeskPalette(dark: colorScheme == .dark) }

    var body: some View {
        GeometryReader { geometry in
            let rail: CGFloat = geometry.size.width >= 960 ? 208 : 171
            let margin: CGFloat = geometry.size.width >= 960 ? 38 : 26
            let contentWidth = geometry.size.width - rail - margin * 2
            HStack(spacing: 0) {
                DeskRail(selection: $model.section)
                    .frame(width: rail)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = model.storageError {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Label(error, systemImage: "externaldrive.badge.exclamationmark")
                                    .font(.callout)
                                    .foregroundStyle(desk.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if model.libraryFile != nil {
                                    Button("Show in Finder") { model.revealLibrary() }
                                        .buttonStyle(DeskButton())
                                }
                            }
                        }
                        switch model.section ?? .reply {
                        case .reply: ComposerView(model: model, wide: contentWidth >= 670)
                        case .voice: VoiceView(model: model)
                        case .projects: ProjectsView(model: model)
                        case .settings: ProviderView(model: model)
                        case .help: HelpView(model: model, openQuickReply: openQuickReply)
                        }
                    }
                    .animation(.easeOut(duration: 0.18), value: model.section)
                    .frame(maxWidth: model.section == .reply ? 1060 : 780, alignment: .leading)
                    .padding(.horizontal, margin)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
                .background(desk.canvas)
            }
        }
        .background(desk.canvas)
        .background(WindowDragEnabler())
        .foregroundStyle(desk.text)
        .tint(desk.violet)
        .environment(\.desk, desk)
        .environment(\.deskTextScale, CGFloat(model.library.settings.textSize.scale))
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
                model.confirmPendingSource()
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
                AppMark(size: 32)
                Text("ReplyAI")
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .tracking(-0.4)
                    .foregroundStyle(desk.text)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 26)

            VStack(spacing: 2) {
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
                    .foregroundStyle(desk.violet)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Library on this Mac")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(desk.text)
                    Text("You decide what to send.")
                        .font(.system(size: 11))
                        .foregroundStyle(desk.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(desk.line).frame(height: 1) }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 25)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(desk.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(desk.line).frame(width: 1) }
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
                    .foregroundStyle(selected ? desk.violet : desk.muted)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .foregroundStyle(selected ? desk.text : desk.muted)
            .background(
                selected ? desk.paper : hover ? desk.paper.opacity(0.55) : .clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .shadow(color: .black.opacity(selected ? (desk.dark ? 0.22 : 0.06) : 0), radius: 3, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: selected)
        .animation(.easeOut(duration: 0.12), value: hover)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
