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
    var canvas: Color { ink(dark ? 0x1D1B25 : 0xF5F2ED) }
    var paper: Color { ink(dark ? 0x292632 : 0xFFFEFC) }
    var inset: Color { ink(dark ? 0x211E2A : 0xF6F4F0) }
    var line: Color { ink(dark ? 0x403A4B : 0xE7E1DA) }
    var text: Color { ink(dark ? 0xF5F0F7 : 0x241F2A) }
    var muted: Color { ink(dark ? 0xB4A9BC : 0x655D6A) }
    var violet: Color { ink(dark ? 0xC8B9FF : 0x5F43A7) }
    var wash: Color { ink(dark ? 0x3B3053 : 0xEDE6F7) }
    var accentButton: Color { ink(dark ? 0xC6B4FB : 0x573D91) }
    var onAccent: Color { ink(dark ? 0x20152E : 0xFFFFFF) }
    var sidebar: Color { ink(0x231E2E) }
    var railText: Color { ink(0xF4EDF9) }
    var railMuted: Color { ink(0xBEB3CA) }
    var railSelection: Color { ink(0x423452) }
    var railAccent: Color { ink(0xD9C8FE) }
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
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(kicker).foregroundStyle(desk.violet)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 47, weight: .regular, design: .serif))
                .tracking(-1.9)
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
    enum Kind { case primary, secondary, quiet }
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
                .foregroundStyle(kind == .primary ? desk.onAccent : kind == .quiet ? desk.muted : desk.text)
                .padding(.horizontal, kind == .primary ? 15 : 11)
                .frame(minHeight: kind == .primary ? 38 : 34)
                .background(fill, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(desk.line, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(
                    color: kind == .primary && enabled ? desk.accentButton.opacity(0.25) : .clear,
                    radius: 6, y: 2
                )
                .contentShape(RoundedRectangle(cornerRadius: 9))
                .opacity(enabled ? 1 : 0.44)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        private var fill: AnyShapeStyle {
            if kind == .primary {
                let top = desk.accentButton.opacity(configuration.isPressed ? 0.78 : hovering ? 0.92 : 1)
                return AnyShapeStyle(LinearGradient(
                    colors: [top, top.opacity(0.9)], startPoint: .top, endPoint: .bottom
                ))
            }
            if configuration.isPressed || hovering { return AnyShapeStyle(desk.wash) }
            return AnyShapeStyle(kind == .secondary ? desk.paper : Color.clear)
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
    @ViewBuilder var content: Content
    @Environment(\.desk) private var desk

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(desk.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
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
    @State private var focused = false
    @Environment(\.desk) private var desk

    var body: some View {
        ZStack(alignment: .topLeading) {
            DeskTextEditor(text: $text, label: label, font: .systemFont(ofSize: 15),
                           textColor: NSColor(desk.text), caretColor: NSColor(desk.violet)) {
                focused = $0
            }
            if text.isEmpty && !placeholder.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(desk.muted)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: height)
        .padding(onPaper ? 5 : 11)
        .background(onPaper ? desk.paper : desk.inset, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if focused || !onPaper {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? desk.violet : desk.line, lineWidth: 1)
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
            .background(desk.inset, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(desk.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
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
