import SwiftUI

/// Editor for `font-codepoint-map` — a repeatable option whose value
/// is `U+XXXX=Family` or `U+XXXX-U+YYYY=Family`. The editor lists
/// existing rows and allows edit/remove/add of individual entries.
struct CodepointMapEditorView: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    @State private var draftRange: String = ""
    @State private var draftFamily: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Codepoint → font family").font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            List {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        TextField("U+E000-U+F8FF", text: Binding(
                            get: { rows[i].range },
                            set: { updateRow(i, range: $0, family: rows[i].family) }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 180)
                        Text("=").foregroundStyle(.secondary)
                        TextField("Font family", text: Binding(
                            get: { rows[i].family },
                            set: { updateRow(i, range: rows[i].range, family: $0) }
                        ))
                        Button {
                            removeRow(i)
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }

                HStack(spacing: 8) {
                    TextField("U+E000-U+F8FF", text: $draftRange)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 180)
                    Text("=").foregroundStyle(.secondary)
                    TextField("Font family", text: $draftFamily)
                    Button {
                        addDraft()
                    } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.borderless)
                        .disabled(draftRange.isEmpty || draftFamily.isEmpty)
                }
            }
        }
    }

    // MARK: - Model

    struct Row: Equatable {
        var range: String
        var family: String
    }

    private var rows: [Row] {
        SettingsValueText.lines(model.currentText(for: option)).compactMap { line -> Row? in
            guard let value = SettingsValueText.parse(line: line, expectedKey: option.name),
                  !value.isEmpty
            else { return nil }
            let parts = value.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Row(
                range: String(parts[0]).trimmingCharacters(in: .whitespaces),
                family: String(parts[1]).trimmingCharacters(in: .whitespaces)
            )
        }
    }

    // MARK: - Mutations

    private func addDraft() {
        var updated = rows
        updated.append(Row(range: draftRange, family: draftFamily))
        draftRange = ""
        draftFamily = ""
        save(updated)
    }

    private func removeRow(_ index: Int) {
        var updated = rows
        guard index < updated.count else { return }
        updated.remove(at: index)
        save(updated)
    }

    private func updateRow(_ index: Int, range: String, family: String) {
        var updated = rows
        guard index < updated.count else { return }
        updated[index] = Row(range: range, family: family)
        save(updated)
    }

    private func save(_ rows: [Row]) {
        if rows.isEmpty {
            model.reset(option)
            return
        }
        let values = rows.map { "\($0.range)=\($0.family)" }
        model.setValue(option, valueText: SettingsValueText.format(key: option.name, values: values))
    }
}
