import SwiftUI

/// Toggle for `kind == .bool`. The current value is parsed from the
/// canonical text; toggling writes the new value straight through
/// the overlay.
struct BoolSettingControl: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Toggle("", isOn: binding)
            .labelsHidden()
            .toggleStyle(.switch)
    }

    private var binding: Binding<Bool> {
        Binding(
            get: {
                let value = SettingsValueText.value(for: option.name, in: model.currentText(for: option))
                return value.lowercased() == "true"
            },
            set: { newValue in
                let text = SettingsValueText.format(
                    key: option.name,
                    value: newValue ? "true" : "false"
                )
                model.setValue(option, valueText: text)
            }
        )
    }
}
