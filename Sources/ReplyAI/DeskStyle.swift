import AppKit
import SwiftUI

private func ink(_ rgb: UInt32) -> Color {
    Color(
        red: Double((rgb >> 16) & 255) / 255,
        green: Double((rgb >> 8) & 255) / 255,
        blue: Double(rgb & 255) / 255
    )
}

struct DeskPalette {
    var dark = false
    // Paper Desk: warm cream surfaces that match the app icon, with its violet as the accent.
    var canvas: Color { ink(dark ? 0x17141F : 0xF7F2E8) }
    var sidebar: Color { ink(dark ? 0x1D1928 : 0xEFE8DA) }
    var paper: Color { ink(dark ? 0x242031 : 0xFFFDF9) }
    var inset: Color { ink(dark ? 0x211D2E : 0xF0E9DC) }
    var line: Color { ink(dark ? 0x383247 : 0xE3D9C8) }
    var text: Color { ink(dark ? 0xF3EEF8 : 0x221C2E) }
    var muted: Color { ink(dark ? 0xADA3BA : 0x665C6E) }
    var violet: Color { ink(dark ? 0xB5A6FF : 0x5540D0) }
    var wash: Color { ink(dark ? 0x322A52 : 0xEAE4FA) }
    var accentTop: Color { ink(dark ? 0xB3A4FF : 0x6B55EA) }
    var accentButton: Color { ink(dark ? 0x9584FF : 0x4F34D6) }
    var onAccent: Color { ink(dark ? 0x170F2E : 0xFFFFFF) }
}

/// The font used in the text editors. The draft is set in serif; everything else uses the system face.
func deskEditorFont(size: CGFloat, serif: Bool) -> NSFont {
    let base = NSFont.systemFont(ofSize: size)
    guard serif, let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

extension EnvironmentValues {
    @Entry var desk = DeskPalette()
}

struct Eyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.7)
    }
}

struct PageTitle: View {
    let kicker: String
    let title: String
    let subtitle: String
    @Environment(\.desk) private var desk

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 34, weight: .regular, design: .serif))
                .tracking(-0.8)
                .foregroundStyle(desk.text)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(desk.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DeskButton: ButtonStyle {
    /// `tinted` is a violet wash fill; `accent` is plain violet text.
    enum Kind { case primary, secondary, quiet, tinted, accent }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: kind)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.desk) private var desk
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .primary ? 15 : 11)
                .frame(minHeight: kind == .primary ? 38 : 34)
                .background(fill, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(desk.line, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(
                    color: kind == .primary && enabled ? desk.accentButton.opacity(0.28) : .clear,
                    radius: 8, y: 3
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .opacity(enabled ? 1 : 0.44)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .primary: desk.onAccent
            case .quiet: desk.muted
            case .tinted, .accent: desk.violet
            case .secondary: desk.text
            }
        }

        private var fill: AnyShapeStyle {
            let active = configuration.isPressed || hovering
            switch kind {
            case .primary:
                let strength = configuration.isPressed ? 0.80 : hovering ? 0.92 : 1
                return AnyShapeStyle(LinearGradient(
                    colors: [desk.accentTop.opacity(strength), desk.accentButton.opacity(strength)],
                    startPoint: .top, endPoint: .bottom
                ))
            case .tinted:
                return AnyShapeStyle(desk.wash.opacity(active ? 0.72 : 1))
            case .secondary:
                return AnyShapeStyle(active ? desk.wash : desk.paper)
            case .quiet, .accent:
                return AnyShapeStyle(active ? desk.wash : Color.clear)
            }
        }
    }
}

struct DeskGlyph: View {
    let symbol: String
    var size: CGFloat = 36
    @Environment(\.desk) private var desk

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.39, weight: .medium))
            .foregroundStyle(desk.violet)
            .frame(width: size, height: size)
            .background(desk.wash, in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 22
    var radius: CGFloat = 20
    @ViewBuilder var content: Content
    @Environment(\.desk) private var desk

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(desk.paper, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(desk.line.opacity(desk.dark ? 0.7 : 0.55), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(desk.dark ? 0.16 : 0.05), radius: 14, y: 6)
            .shadow(color: .black.opacity(desk.dark ? 0.10 : 0.03), radius: 2, y: 1)
    }
}

struct WritingField: View {
    @Binding var text: String
    let placeholder: String
    let label: String
    var height: CGFloat = 90
    var onPaper = false
    var size: CGFloat = 15
    var serif = false
    @State private var focused = false
    @Environment(\.desk) private var desk

    var body: some View {
        ZStack(alignment: .topLeading) {
            DeskTextEditor(text: $text, label: label, font: deskEditorFont(size: size, serif: serif),
                           textColor: NSColor(desk.text), caretColor: NSColor(desk.violet),
                           lineSpacing: serif ? size * 0.42 : 4) {
                focused = $0
            }
            if text.isEmpty && !placeholder.isEmpty {
                Text(placeholder)
                    .font(.system(size: size, design: serif ? .serif : .default))
                    .foregroundStyle(desk.muted)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: height)
        .padding(.horizontal, onPaper ? 5 : 16)
        .padding(.vertical, onPaper ? 5 : 13)
        .background(onPaper ? desk.paper : desk.inset, in: RoundedRectangle(cornerRadius: onPaper ? 8 : 14))
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: onPaper ? 8 : 14)
                    .strokeBorder(desk.violet, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

struct DeskField: ViewModifier {
    @Environment(\.desk) private var desk

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(desk.inset, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(desk.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

/// The app's own icon, as macOS resolves it for the running bundle.
struct AppMark: View {
    var size: CGFloat = 30

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct DeskEmptyState: View {
    let icon: String
    let title: String
    let text: String
    @Environment(\.desk) private var desk

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            DeskGlyph(symbol: icon, size: 42)
            Text(title)
                .font(.system(size: 26, design: .serif))
                .foregroundStyle(desk.text)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(desk.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SheetHeader: View {
    let kicker: String
    let title: String
    @Environment(\.desk) private var desk

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(kicker).foregroundStyle(desk.violet).accessibilityHidden(true)
            Text(title)
                .font(.system(size: 31, design: .serif))
                .foregroundStyle(desk.text)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
