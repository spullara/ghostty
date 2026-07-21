import SwiftUI

/// 16×16 grid of the 256 terminal color palette entries. Each
/// swatch opens a ColorPicker; overridden indices show a small dot
/// and can be reset individually or all at once. Emits the canonical
/// `palette = N=#rrggbb\n` (one line per index) form on save.
struct PaletteEditorView: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    @State private var selection: Int? = nil

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 4), count: 16)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("256-color palette").font(.headline)
                Spacer()
                Button("Reset all") { resetAll() }
                    .disabled(overriddenIndices.isEmpty)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<256, id: \.self) { i in
                    swatch(index: i)
                }
            }
            if let sel = selection {
                Divider()
                editor(for: sel)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    @ViewBuilder
    private func swatch(index i: Int) -> some View {
        let color = paletteColor(index: i)
        Button {
            selection = i
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(selection == i ? Color.accentColor : Color.gray.opacity(0.3),
                                    lineWidth: selection == i ? 2 : 0.5)
                    )
                if overriddenIndices.contains(i) {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Index \(i)")
    }

    @ViewBuilder
    private func editor(for index: Int) -> some View {
        HStack(spacing: 12) {
            Text("Index \(index)")
                .font(.system(.body, design: .monospaced))
                .frame(width: 80, alignment: .leading)
            ColorPicker(
                "",
                selection: Binding(
                    get: { paletteColor(index: index) },
                    set: { setColor(index: index, color: $0) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            Text(hexString(color: paletteColor(index: index)))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reset") { resetIndex(index) }
                .disabled(!overriddenIndices.contains(index))
        }
    }

    // MARK: - State access

    /// Parsed effective palette (256 entries) merged with overlay
    /// overrides. Overlay lines take precedence per-index.
    private var effectivePalette: [Color] {
        var out = defaultPalette()
        // First, apply effective values (from the running config).
        for (idx, color) in parseLines(model.effectiveValues[option.name] ?? "") {
            if idx >= 0 && idx < 256 { out[idx] = color }
        }
        // Then, apply the overlay on top so pending edits are visible.
        if let overlay = model.overlay.entries[option.name] {
            for (idx, color) in parseLines(overlay) {
                if idx >= 0 && idx < 256 { out[idx] = color }
            }
        }
        return out
    }

    private var overriddenIndices: Set<Int> {
        guard let overlay = model.overlay.entries[option.name] else { return [] }
        return Set(parseLines(overlay).map { $0.0 })
    }

    private func paletteColor(index i: Int) -> Color {
        effectivePalette[i]
    }

    // MARK: - Mutations

    private func setColor(index i: Int, color: Color) {
        var current = Dictionary(
            uniqueKeysWithValues: parseLines(model.overlay.entries[option.name] ?? "")
        )
        current[i] = color
        emit(entries: current)
    }

    private func resetIndex(_ i: Int) {
        var current = Dictionary(
            uniqueKeysWithValues: parseLines(model.overlay.entries[option.name] ?? "")
        )
        current.removeValue(forKey: i)
        if current.isEmpty {
            model.reset(option)
        } else {
            emit(entries: current)
        }
    }

    private func resetAll() { model.reset(option) }

    private func emit(entries: [Int: Color]) {
        let sorted = entries.sorted { $0.key < $1.key }
        let values = sorted.map { "\($0.key)=\(hexString(color: $0.value))" }
        model.setValue(option, valueText: SettingsValueText.format(key: option.name, values: values))
    }

    // MARK: - Parsing helpers (internal — exposed for tests)

    static func parsePaletteLines(_ text: String, key: String) -> [(Int, Color)] {
        var out: [(Int, Color)] = []
        for line in SettingsValueText.lines(text) {
            guard let value = SettingsValueText.parse(line: line, expectedKey: key) else { continue }
            // Value may be either a single "N=#rrggbb" entry or a
            // comma-separated color list; support both formats.
            for token in value.split(separator: ",") {
                let parts = token.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2,
                      let idx = parseIndex(parts[0]),
                      let color = ColorSettingControl.color(from: parts[1])
                else { continue }
                out.append((idx, color))
            }
        }
        return out
    }

    private func parseLines(_ text: String) -> [(Int, Color)] {
        Self.parsePaletteLines(text, key: option.name)
    }

    private static func parseIndex(_ s: String) -> Int? {
        if s.hasPrefix("0x") || s.hasPrefix("0X") { return Int(s.dropFirst(2), radix: 16) }
        if s.hasPrefix("0o") || s.hasPrefix("0O") { return Int(s.dropFirst(2), radix: 8) }
        if s.hasPrefix("0b") || s.hasPrefix("0B") { return Int(s.dropFirst(2), radix: 2) }
        return Int(s)
    }

    private func hexString(color: Color) -> String {
        ColorSettingControl.hex(from: color) ?? "#000000"
    }

    /// A reasonable default 256-color palette (VGA + xterm 216 + gray
    /// ramp). Only used until the config publishes effective values.
    private func defaultPalette() -> [Color] {
        var out: [Color] = []
        let base: [(Int, Int, Int)] = [
            (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
            (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
            (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
            (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)
        ]
        for c in base { out.append(color(r: c.0, g: c.1, b: c.2)) }
        let levels = [0, 95, 135, 175, 215, 255]
        for r in 0..<6 { for g in 0..<6 { for b in 0..<6 {
            out.append(color(r: levels[r], g: levels[g], b: levels[b]))
        }}}
        for i in 0..<24 {
            let v = 8 + i * 10
            out.append(color(r: v, g: v, b: v))
        }
        return out
    }

    private func color(r: Int, g: Int, b: Int) -> Color {
        Color(.sRGB,
              red: Double(r) / 255.0,
              green: Double(g) / 255.0,
              blue: Double(b) / 255.0,
              opacity: 1)
    }
}
