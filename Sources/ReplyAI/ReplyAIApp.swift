import AppKit
import os
import ReplyCore
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
                Button("Copy Draft") { model.copyDraft() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
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
        if let status = model.shortcutRegistrationStatus, status != 0 {
            Text("Shortcut unavailable. Choose another in Settings.")
        }
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
    private var capturing = false

    func showQuickReply() { quickReply.show() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        let model = AppModel.shared
        model.shortcutRegistrationStatus = selectionShortcut.start(model.library.settings.shortcut) { [weak self] in
            Task { @MainActor [weak self] in
                // One capture at a time: a second press mid-capture would snapshot the wrong clipboard.
                guard let self, !self.capturing else { return }
                self.capturing = true
                defer { self.capturing = false }
                let capture = await SelectionCapture.focusedText()
                self.quickReply.show(capture)
            }
        }
        if let status = model.shortcutRegistrationStatus, status != 0 {
            appLog.error("Global shortcut registration failed with status \(status, privacy: .public).")
        }
        model.applyShortcut = { [weak self] preset in
            let status = self?.selectionShortcut.register(preset) ?? 0
            if status != 0 { appLog.error("Global shortcut registration failed with status \(status, privacy: .public).") }
            return status
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.flushSave()
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
