import SwiftUI

/// Text field for numeric-like kinds (`int`, `float`, `duration`).
///
/// We intentionally do not enforce numeric-only input in the field
/// itself: several numeric options accept human units (percent,
/// units, duration strings like `250ms`), and we want the Zig
/// loader to remain the authoritative parser. Users get feedback
/// via the diagnostics list (Phase 4) when they enter an invalid
/// value. The overlay only stores what the user typed.
struct NumberSettingControl: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        TextField("", text: binding)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: 180)
    }

    private var binding: Binding<String> {
        Binding(
            get: { SettingsValueText.value(for: option.name, in: model.currentText(for: option)) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                let text = SettingsValueText.format(key: option.name, value: trimmed)
                model.setValue(option, valueText: text)
            }
        )
    }
}
