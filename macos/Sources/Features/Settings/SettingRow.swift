import SwiftUI

/// A single row in the option list: name, control, override
/// indicator, reset button, and a disclosure with the docs.
struct SettingRow: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    @State private var showDocs: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.name)
                            .font(.system(.body, design: .monospaced))
                        if model.isOverridden(option) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .help("Overridden by the Settings window")
                        }
                        if let badge = platformBadge {
                            Text(badge)
                                .font(.caption2).fontWeight(.medium)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                                .help("This option only applies to \(badge).")
                        }
                    }
                    if !option.docs.isEmpty {
                        Button {
                            showDocs.toggle()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: showDocs ? "chevron.down" : "chevron.right")
                                Text(showDocs ? "Hide description" : "Show description")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                SettingControl(option: option, model: model)
                    .frame(minWidth: 200, maxWidth: 320, alignment: .trailing)
                Button {
                    model.reset(option)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .disabled(!model.isOverridden(option))
                .help("Reset to the default (or your primary config file's value)")
            }

            if showDocs, !option.docs.isEmpty {
                Text(option.docs)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// Short label indicating a non-macOS platform, shown as a pill
    /// next to the option name so users know why a control might be
    /// inert on their system.
    private var platformBadge: String? {
        let name = option.name
        if name.hasPrefix("gtk-") || name.hasPrefix("adw-") { return "GTK" }
        if name.hasPrefix("linux-") { return "Linux" }
        if name == "class" || name == "x11-instance-name" { return "Linux" }
        return nil
    }
}

/// Dispatches to a per-kind control view. Kinds without a dedicated
/// editor yet fall through to the generic monospaced text field so
/// every option remains addressable.
struct SettingControl: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        switch option.kind {
        case .bool:
            BoolSettingControl(option: option, model: model)
        case .enum:
            EnumSettingControl(option: option, model: model)
        case .int, .float, .duration:
            NumberSettingControl(option: option, model: model)
        case .color:
            ColorSettingControl(option: option, model: model)
        case .path:
            PathSettingControl(option: option, model: model)
        case .repeatablePath:
            EditorSheetControl(option: option, model: model, summary: pathSummary) {
                CustomShaderEditorView(option: option, model: model)
            }
        case .palette:
            EditorSheetControl(option: option, model: model, summary: "256 colors") {
                PaletteEditorView(option: option, model: model)
            }
        case .keybinds:
            EditorSheetControl(option: option, model: model, summary: keybindSummary) {
                KeybindEditorView(option: option, model: model)
            }
        case .commandPaletteEntry:
            EditorSheetControl(option: option, model: model, summary: commandPaletteSummary) {
                CommandPaletteEntryEditorView(option: option, model: model)
            }
        case .codepointMap:
            EditorSheetControl(option: option, model: model, summary: codepointMapSummary) {
                CodepointMapEditorView(option: option, model: model)
            }
        case .theme:
            EditorSheetControl(option: option, model: model, summary: themeSummary) {
                ThemePickerView(option: option, model: model)
            }
        case .repeatableString where option.name.hasPrefix("font-family"),
             .string where option.name.hasPrefix("font-family"):
            EditorSheetControl(option: option, model: model, summary: fontFamilySummary) {
                FontFamilyPickerView(option: option, model: model)
            }
        default:
            TextSettingControl(option: option, model: model)
        }
    }

    private var pathSummary: String {
        let n = SettingsValueText.lines(model.currentText(for: option)).count
        return n == 0 ? "None" : "\(n) file\(n == 1 ? "" : "s")"
    }
    private var keybindSummary: String {
        let n = SettingsValueText.lines(model.currentText(for: option)).count
        return n == 0 ? "None" : "\(n) binding\(n == 1 ? "" : "s")"
    }
    private var commandPaletteSummary: String {
        let n = SettingsValueText.lines(model.currentText(for: option)).count
        return n == 0 ? "None" : "\(n) entr\(n == 1 ? "y" : "ies")"
    }
    private var codepointMapSummary: String {
        let n = SettingsValueText.lines(model.currentText(for: option)).count
        return n == 0 ? "None" : "\(n) mapping\(n == 1 ? "" : "s")"
    }
    private var themeSummary: String {
        let v = SettingsValueText.value(for: option.name, in: model.currentText(for: option))
        return v.isEmpty ? "System default" : v
    }
    private var fontFamilySummary: String {
        let items = SettingsValueText.lines(model.currentText(for: option)).compactMap {
            SettingsValueText.parse(line: $0, expectedKey: option.name)
        }.filter { !$0.isEmpty }
        if items.isEmpty { return "System default" }
        if items.count == 1 { return items[0] }
        return "\(items[0]) +\(items.count - 1)"
    }
}
