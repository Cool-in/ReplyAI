import AppKit
@preconcurrency import ApplicationServices
import Carbon
import ReplyCore

enum SelectionCapture: Equatable {
    case selected(String)
    case needsPermission
    case noSelection
    case unavailable

    /// Reads the selection through accessibility. Many browsers and Electron apps do not expose
    /// selected text that way, so when that comes back empty this falls back to copying it.
    @MainActor static func focusedText() async -> Self {
        let direct = accessibleSelection()
        switch direct {
        case .selected, .needsPermission:
            return direct
        case .noSelection, .unavailable:
            guard !focusIsSecureField(), let text = await copiedSelection() else { return direct }
            return .selected(text)
        }
    }

    @MainActor private static func frontApplication() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        return application
    }

    /// True when the focused control is a password field. The copy fallback never runs there.
    @MainActor private static func focusIsSecureField() -> Bool {
        guard let application = frontApplication() else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let element = value as! AXUIElement
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        return subrole as? String == kAXSecureTextFieldSubrole
    }

    /// Sends Copy to the front app, reads what lands on the clipboard, then puts the clipboard back.
    @MainActor private static func copiedSelection() async -> String? {
        guard frontApplication() != nil else { return nil }
        let pasteboard = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        let before = pasteboard.changeCount
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        var text: String?
        for _ in 0..<16 {
            try? await Task.sleep(for: .milliseconds(25))
            if pasteboard.changeCount != before {
                text = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != before {
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    @MainActor private static func accessibleSelection() -> Self {
        guard AXIsProcessTrusted() else { return .needsPermission }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .noSelection }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        var value: CFTypeRef?
        let focus = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value)
        guard focus == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return focus == .noValue ? .noSelection : .unavailable
        }

        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != kAXSecureTextFieldSubrole else { return .unavailable }

        var selected: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected)
        if result == .noValue { return .noSelection }
        guard result == .success else { return .unavailable }
        guard let text = selected as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .noSelection }
        return .selected(text)
    }

    @MainActor static func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    var message: String? {
        switch self {
        case .selected: nil
        case .needsPermission: "Enable Accessibility access for shortcut capture, then select text in the other app and press the shortcut again. You can also use Services or Paste."
        case .noSelection: "Select text in the other app and press the shortcut again, or copy the text and choose Paste here."
        case .unavailable: "This selection wasn’t available to the shortcut. Try the app’s Services menu, or copy the text and choose Paste here."
        }
    }
}

@MainActor
final class SelectionShortcut {
    private static let signature: OSType = 0x52504C59 // RPLY
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    func start(_ preset: ShortcutPreset, action: @escaping () -> Void) -> OSStatus {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let target = GetApplicationEventTarget()
        let install = InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                         EventParamType(typeEventHotKeyID), nil,
                                         MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard read == noErr, id.signature == 0x52504C59, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<SelectionShortcut>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)

        guard install == noErr else { return install }
        return register(preset)
    }

    /// Swaps the registered shortcut. On failure nothing is registered, and another preset can be tried.
    func register(_ preset: ShortcutPreset) -> OSStatus {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        let key: Int
        let modifiers: Int
        switch preset {
        case .optionShiftR:
            key = kVK_ANSI_R
            modifiers = optionKey | shiftKey
        case .controlOptionR:
            key = kVK_ANSI_R
            modifiers = controlKey | optionKey
        case .controlOptionSpace:
            key = kVK_Space
            modifiers = controlKey | optionKey
        }
        let status = RegisterEventHotKey(UInt32(key), UInt32(modifiers),
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &registration)
        if status != noErr { registration = nil }
        return status
    }

    func stop() {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil
        handler = nil
        action = nil
    }
}
