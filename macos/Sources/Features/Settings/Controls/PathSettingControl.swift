import SwiftUI
import AppKit

/// Path picker for `kind == .path` and `.repeatablePath`.
///
/// Single-path variants render one row with a "Choose…" button that
/// opens `NSOpenPanel`. Repeatable variants render one row per
/// existing entry plus a "+" button to add another.
///
/// Values are stored verbatim (no tilde expansion) so users see the
/// exact string Ghostty will parse.
struct PathSettingControl: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        if option.kind == .repeatablePath {
            repeatableBody
        } else {
            singleRow(index: 0, value: values.first ?? "")
        }
    }

    private var values: [String] {
        let text = model.currentText(for: option)
        return SettingsValueText.lines(text).compactMap {
            SettingsValueText.parse(line: $0, expectedKey: option.name)
        }
    }

    private var repeatableBody: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { idx, val in
                singleRow(index: idx, value: val)
            }
            Button {
                var next = values
                next.append("")
                write(next)
            } label: {
                Label("Add path", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func singleRow(index: Int, value: String) -> some View {
        HStack(spacing: 4) {
            TextField("", text: Binding(
                get: { value },
                set: { newValue in updateAt(index, to: newValue) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            Button {
                choose(replacingIndex: index)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Choose file…")
        }
    }

    private func updateAt(_ index: Int, to newValue: String) {
        var next = values
        while next.count <= index { next.append("") }
        next[index] = newValue.trimmingCharacters(in: .whitespaces)
        write(next)
    }

    private func choose(replacingIndex index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateAt(index, to: url.path)
    }

    private func write(_ values: [String]) {
        let cleaned = values.filter { !$0.isEmpty }
        let text: String
        if option.kind == .repeatablePath {
            text = SettingsValueText.format(key: option.name, values: cleaned)
        } else {
            text = SettingsValueText.format(key: option.name, value: cleaned.first ?? "")
        }
        model.setValue(option, valueText: text)
    }
}
