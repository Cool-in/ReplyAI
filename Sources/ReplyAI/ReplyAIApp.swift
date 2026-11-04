import AppKit
import SwiftUI

@main
struct ReplyAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("ReplyAI", id: "composer") {
            RootView(model: model, openQuickReply: { delegate.showQuickReply() })
                .frame(minWidth: 780, minHeight: 610)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandMenu("Reply") {
                Button("Paste as Comment") { model.pasteSource() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("New Reply") { model.clear(); model.section = .reply }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("ReplyAI", systemImage: "bubble.left.and.bubble.right.fill") {
            MenuActions(model: model, quickReply: { delegate.showQuickReply() })
        }
    }
}

struct MenuActions: View {
    let model: AppModel
    let quickReply: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Quick Reply", action: quickReply)
        Button("Open ReplyAI") { show() }
        Button("Paste and Open ReplyAI") { show(); model.pasteSource() }
        Divider()
        Button("Quit ReplyAI") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show() {
        openWindow(id: "composer")
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let quickReply = QuickReplyController()
    private let selectionShortcut = SelectionShortcut()

    func showQuickReply() { quickReply.show() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        AppModel.shared.shortcutRegistrationStatus = selectionShortcut.start { [weak self] in
            let capture = SelectionCapture.focusedText()
            self?.quickReply.show(capture)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionShortcut.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.showWindow?() }
        return true
    }

    @objc(draftReply:userData:error:)
    func draftReply(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let selection = pasteboard.string(forType: .string),
              !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error?.pointee = "ReplyAI needs a text selection."
            return
        }
        Task { @MainActor in quickReply.show(.selected(selection)) }
    }
}
