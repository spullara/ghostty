import SwiftUI

/// Editor for the `command-palette-entry` repeatable option. Each
/// row has title/description/action fields. Action strings are
/// hand-edited for now — the picker autocompletes against the
/// schema's `keybindActions` catalog.
struct CommandPaletteEntryEditorView: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    @State private var draftTitle: String = ""
    @State private var draftDescription: String = ""
    @State private var draftAction: String = "ignore"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Command palette entries").font(.headline)
                Spacer()
                Text("\(entries.count)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding()
            Divider()

            List {
                ForEach(entries.indices, id: \.self) { i in
                    entryRow(index: i)
                }
                addRow
            }
        }
    }

    @ViewBuilder
    private func entryRow(index i: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Title", text: Binding(
                    get: { entries[i].title },
                    set: { update(i, title: $0) }
                ))
                Button {
                    remove(i)
                } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
            }
            TextField("Description (optional)", text: Binding(
                get: { entries[i].description },
                set: { update(i, description: $0) }
            ))
            .foregroundStyle(.secondary)
            .font(.callout)
            HStack {
                Text("Action:").foregroundStyle(.secondary).font(.caption)
                TextField("action", text: Binding(
                    get: { entries[i].action },
                    set: { update(i, action: $0) }
                ))
                .font(.system(.body, design: .monospaced))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var addRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("New title", text: $draftTitle)
                Button {
                    addDraft()
                } label: { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.borderless)
                    .disabled(draftTitle.isEmpty || draftAction.isEmpty)
            }
            TextField("Description (optional)", text: $draftDescription)
                .foregroundStyle(.secondary)
                .font(.callout)
            HStack {
                Text("Action:").foregroundStyle(.secondary).font(.caption)
                Picker("", selection: $draftAction) {
                    ForEach(model.schema.keybindActions) { a in
                        Text(a.name).tag(a.name)
                    }
                }
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data

    struct Entry: Equatable {
        var title: String
        var description: String
        var action: String
    }

    private var entries: [Entry] {
        SettingsValueText.lines(model.currentText(for: option)).compactMap { line in
            guard let value = SettingsValueText.parse(line: line, expectedKey: option.name),
                  !value.isEmpty
            else { return nil }
            return Self.parse(value: value)
        }
    }

    /// Parse a canonical entry like
    /// `title:"Foo",description:"Bar",action:"ignore"`. Also accepts
    /// unquoted values for hand-written configs.
    static func parse(value: String) -> Entry? {
        let fields = splitCSVRespectingQuotes(value)
        var title = ""
        var description = ""
        var action = ""
        for field in fields {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let key = field[..<colon].trimmingCharacters(in: .whitespaces)
            let raw = field[field.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let unquoted = stripQuotes(String(raw))
            switch key {
            case "title": title = unquoted
            case "description": description = unquoted
            case "action": action = unquoted
            default: break
            }
        }
        guard !title.isEmpty || !action.isEmpty else { return nil }
        return Entry(title: title, description: description, action: action)
    }

    // MARK: - Mutations

    private func update(_ index: Int, title: String? = nil, description: String? = nil, action: String? = nil) {
        var list = entries
        guard index < list.count else { return }
        if let t = title { list[index].title = t }
        if let d = description { list[index].description = d }
        if let a = action { list[index].action = a }
        save(list)
    }

    private func remove(_ index: Int) {
        var list = entries
        guard index < list.count else { return }
        list.remove(at: index)
        save(list)
    }

    private func addDraft() {
        var list = entries
        list.append(Entry(title: draftTitle, description: draftDescription, action: draftAction))
        draftTitle = ""
        draftDescription = ""
        save(list)
    }

    private func save(_ list: [Entry]) {
        if list.isEmpty {
            model.reset(option)
            return
        }
        let values = list.map { formatEntry($0) }
        model.setValue(option, valueText: SettingsValueText.format(key: option.name, values: values))
    }

    static func formatEntry(_ e: Entry) -> String {
        var out = "title:\"\(escape(e.title))\""
        if !e.description.isEmpty {
            out += ",description:\"\(escape(e.description))\""
        }
        out += ",action:\"\(escape(e.action))\""
        return out
    }

    private func formatEntry(_ e: Entry) -> String { Self.formatEntry(e) }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func stripQuotes(_ s: String) -> String {
        var value = s
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Comma-splits `value`, respecting double-quoted substrings so
    /// commas inside titles/descriptions don't break the parse.
    static func splitCSVRespectingQuotes(_ value: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for ch in value {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" { current.append(ch); escaped = true; continue }
            if ch == "\"" { inQuotes.toggle(); current.append(ch); continue }
            if ch == "," && !inQuotes {
                out.append(current); current = ""
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
