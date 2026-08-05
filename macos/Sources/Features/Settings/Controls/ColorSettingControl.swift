import SwiftUI

/// Color picker for `kind == .color`. Optional colors get a
/// "Default" affordance; colors with `specialValues` (like
/// `cell-foreground`) get a menu of those non-color tokens.
///
/// Values round-trip as `#rrggbb` hex strings. Ghostty's config
/// loader accepts several color syntaxes, but the picker always
/// writes canonical hex so users see stable text in the overlay.
struct ColorSettingControl: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        HStack(spacing: 6) {
            if let specials = option.specialValues, !specials.isEmpty {
                Menu {
                    if option.optional {
                        Button("Default") { setRaw("") }
                    }
                    ForEach(specials, id: \.self) { special in
                        Button(special) { setRaw(special) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Choose a special value like \(specials.first ?? "")")
            }
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
        }
    }

    private var currentText: String {
        SettingsValueText.value(for: option.name, in: model.currentText(for: option))
    }

    private func setRaw(_ value: String) {
        model.setValue(option, valueText: SettingsValueText.format(key: option.name, value: value))
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Self.color(from: currentText) ?? .white },
            set: { newColor in setRaw(Self.hex(from: newColor) ?? "") }
        )
    }

    /// Parse `#rrggbb` (with or without `#`) into a `Color`. Returns
    /// `nil` for special tokens or empty text; callers pick a
    /// sensible default in that case.
    static func color(from text: String) -> Color? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xff) / 255.0
        let g = Double((v >> 8) & 0xff) / 255.0
        let b = Double(v & 0xff) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Serialize a `Color` back to `#rrggbb` via NSColor conversion
    /// through the device RGB space.
    static func hex(from color: Color) -> String? {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
