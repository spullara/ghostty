import SwiftUI

/// Generic monospaced text field for kinds without a dedicated
/// editor yet (`string`, `command`, `custom`, `theme`, `font-style`,
/// `packed-bools`, `codepoint-map`, `keybinds`, `palette`,
/// `command-palette-entry`, `repeatable-string`, `color-list`,
/// `string-map`).
///
/// Phase 3 adds real editors for the specialized kinds. Until then
/// this fallback keeps every option addressable — the user can paste
/// canonical text and it round-trips exactly.
struct TextSettingControl: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        TextField("", text: binding, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1...6)
    }

    /// Binds against the *entire* value portion of the canonical
    /// text (joined with newlines for repeatable types) so users can
    /// hand-edit multi-line values without the field mangling them.
    private var binding: Binding<String> {
        Binding(
            get: {
                let text = model.currentText(for: option)
                let values = SettingsValueText.lines(text).compactMap {
                    SettingsValueText.parse(line: $0, expectedKey: option.name)
                }
                return values.joined(separator: "\n")
            },
            set: { newValue in
                let values = newValue.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                let text: String
                if values.count <= 1 {
                    text = SettingsValueText.format(
                        key: option.name,
                        value: values.first ?? ""
                    )
                } else {
                    text = SettingsValueText.format(
                        key: option.name,
                        values: values
                    )
                }
                model.setValue(option, valueText: text)
            }
        )
    }
}
