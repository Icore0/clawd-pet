import SwiftUI

/// Wigglet's design system, matching the website: ink background, square corners, hairlines,
/// uppercase mono labels, one clay accent. Everything in the app's own UI draws from here.
enum W {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255, opacity: a)
    }
    static let bg = hex(0x141413)
    static let panel = hex(0x1E1D1B)
    static let raised = hex(0x1A1A18)
    static let ink = hex(0xFAF9F5)
    static let ink2 = hex(0xB0AEA5)
    static let ink3 = hex(0x87867F)
    static let ink4 = hex(0x5E5D59)
    static let line = hex(0xFAF9F5, 0.16)
    static let soft = hex(0xFAF9F5, 0.09)
    static let clay = hex(0xD97757)
    static let ok = hex(0x7CB98A)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

/// "01 / SETUP" style label.
struct MonoLabel: View {
    let text: String
    var color: Color = W.ink3
    var size: CGFloat = 11
    var body: some View {
        Text(text.uppercased()).font(W.mono(size)).tracking(0.6).foregroundStyle(color)
    }
}

struct Hairline: View {
    var strong = false
    var body: some View { Rectangle().fill(strong ? W.line : W.soft).frame(height: 1) }
}

/// Big section heading with the website's tight tracking.
struct Heading: View {
    let text: String
    var size: CGFloat = 40
    var body: some View {
        Text(text).font(W.sans(size)).tracking(-size * 0.035).foregroundStyle(W.ink).fixedSize(horizontal: false, vertical: true)
    }
}

struct Keycap: View {
    let text: String
    var active = false
    var body: some View {
        Text(text).font(W.mono(10.5, .medium)).foregroundStyle(active ? W.clay : W.ink2)
            .frame(minWidth: 20, minHeight: 20).padding(.horizontal, 3)
            .overlay(Rectangle().stroke(active ? W.clay : W.line, lineWidth: 1))
    }
}

struct Chip: View {
    let text: String
    var color: Color = W.ink3
    var filled = false
    var body: some View {
        Text(text.uppercased()).font(W.mono(10, .semibold)).tracking(0.5)
            .foregroundStyle(filled ? W.bg : color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Rectangle().fill(filled ? color : Color.clear))
            .overlay(Rectangle().stroke(color.opacity(filled ? 0 : 0.7), lineWidth: 1))
    }
}

/// Square buttons: `.solid` (cream, the primary action), `.clay` (accent), `.line` (hairline).
struct WButton: ButtonStyle {
    enum Kind { case solid, clay, line }
    var kind: Kind = .solid
    var small = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = kind == .solid ? W.ink : (kind == .clay ? W.clay : Color.clear)
        let text: Color = kind == .line ? W.ink : W.bg
        configuration.label
            .font(small ? W.mono(11, .semibold) : W.sans(14, .medium))
            .tracking(small ? 0.5 : 0)
            .foregroundStyle(text.opacity(enabled ? 1 : 0.45))
            .padding(.horizontal, small ? 11 : 18).frame(height: small ? 28 : 38)
            .background(Rectangle().fill(configuration.isPressed ? (kind == .line ? W.panel : W.clay) : fill.opacity(enabled ? 1 : 0.35)))
            .overlay(Rectangle().stroke(kind == .line ? W.line : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Square switch: clay track with a cream knob when on.
struct SquareToggle: View {
    @Binding var isOn: Bool
    var label = ""
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle().fill(isOn ? W.clay : W.raised).frame(width: 38, height: 20)
                    .overlay(Rectangle().stroke(isOn ? W.clay : W.line, lineWidth: 1))
                Rectangle().fill(isOn ? W.ink : W.ink3).frame(width: 14, height: 14).padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isButton)
    }
}

/// Square segmented picker.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                Button { selection = o.0 } label: {
                    Text(o.1.uppercased()).font(W.mono(10.5, .semibold)).tracking(0.5)
                        .foregroundStyle(selection == o.0 ? W.bg : W.ink2)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Rectangle().fill(selection == o.0 ? W.ink : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < options.count - 1 { Rectangle().fill(W.line).frame(width: 1, height: 28) }
            }
        }
        .overlay(Rectangle().stroke(W.line, lineWidth: 1))
    }
}

/// A website-style row: label column, description, control on the right, hairline below.
struct WRow<Trailing: View>: View {
    var number = ""
    let title: String
    var detail = ""
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                if !number.isEmpty { Text(number).font(W.mono(11)).foregroundStyle(W.ink4).frame(width: 26, alignment: .leading) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(W.sans(16)).foregroundStyle(W.ink)
                    if !detail.isEmpty { Text(detail).font(W.sans(13)).foregroundStyle(W.ink3).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.vertical, 16)
            Hairline()
        }
    }
}

extension View {
    /// Square ink panel with a hairline edge: the website's card, used for floating UI too.
    func wPanel(_ fill: Color = W.panel) -> some View {
        background(Rectangle().fill(fill.opacity(0.97)))
            .overlay(Rectangle().stroke(W.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}
