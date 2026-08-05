import SwiftUI

/// Picker for `kind == .enum`. Values come from the schema; the
/// current value is derived from the canonical text. Optional enums
/// get an explicit "Default" row (empty value) so users can clear
/// their overlay entry without hitting the reset button.
struct EnumSettingControl: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Picker("", selection: binding) {
            if option.optional {
                Text("Default").tag("")
            }
            ForEach(option.values ?? [], id: \.self) { value in
                Text(value).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var binding: Binding<String> {
        Binding(
            get: { SettingsValueText.value(for: option.name, in: model.currentText(for: option)) },
            set: { newValue in
                let text = SettingsValueText.format(key: option.name, value: newValue)
                model.setValue(option, valueText: text)
            }
        )
    }
}
