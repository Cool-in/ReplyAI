import AppKit
@preconcurrency import ApplicationServices
import Carbon

enum SelectionCapture: Equatable {
    case selected(String)
    case needsPermission
    case noSelection
    case unavailable

    @MainActor static func focusedText() -> Self {
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
        case .needsPermission: "Enable Accessibility access for shortcut capture, then select text in the other app and press ⌥⇧R again. You can also use Services or Paste."
        case .noSelection: "Select text in the other app and press ⌥⇧R again, or copy the text and choose Paste here."
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

    func start(action: @escaping () -> Void) -> OSStatus {
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
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(optionKey | shiftKey),
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         target, OptionBits(kEventHotKeyExclusive), &registration)
        if status != noErr { stop() }
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
