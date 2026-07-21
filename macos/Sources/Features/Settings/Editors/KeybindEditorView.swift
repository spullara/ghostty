import AppKit
import SwiftUI

/// Editor for the `keybind` repeatable option. Renders each binding
/// as a table row (trigger + action) and lets users add, remove, and
/// edit them individually. Overlay semantics: added rows override
/// same-trigger user bindings; deleting a row removes the overlay
/// entry but does not clear a user-config binding.
struct KeybindEditorView: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    @State private var selection: Int? = nil
    @State private var draftTrigger: String = ""
    @State private var draftAction: String = "ignore"
    @State private var draftArg: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keybindings").font(.headline)
                Spacer()
                Text("\(bindings.count) binding\(bindings.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding()

            Divider()

            List(selection: $selection) {
                ForEach(bindings.indices, id: \.self) { i in
                    HStack {
                        Text(bindings[i].trigger)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 200, alignment: .leading)
                        Text(bindings[i].action)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .frame(minHeight: 200)

            Divider()

            newRow
        }
    }

    @ViewBuilder
    private var newRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trigger").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. cmd+shift+r", text: $draftTrigger)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                        KeybindRecorderButton(trigger: $draftTrigger)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        actionPicker
                        if actionArgumentKind == .int || actionArgumentKind == .string || actionArgumentKind == .custom {
                            TextField(argPlaceholder, text: $draftArg)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        } else if actionArgumentKind == .enum, let values = currentActionValues() {
                            Picker("", selection: $draftArg) {
                                ForEach(values, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                    }
                }
                Spacer()
                Button {
                    addDraft()
                } label: { Label("Add", systemImage: "plus") }
                    .disabled(draftTrigger.isEmpty)
            }
            HStack {
                Button("Remove selected") {
                    removeSelected()
                }
                .disabled(selection == nil)
                Spacer()
            }
        }
        .padding()
    }

    @ViewBuilder
    private var actionPicker: some View {
        Picker("", selection: $draftAction) {
            ForEach(model.schema.keybindActions) { action in
                Text(action.name).tag(action.name)
            }
        }
        .labelsHidden()
        .frame(width: 220)
    }

    private var actionArgumentKind: SettingsSchema.KeybindAction.ArgumentKind {
        model.schema.keybindActions.first { $0.name == draftAction }?.argument.kind ?? .none
    }

    private var argPlaceholder: String {
        switch actionArgumentKind {
        case .int: return "42"
        case .string: return "text"
        case .custom: return "custom"
        default: return ""
        }
    }

    private func currentActionValues() -> [String]? {
        model.schema.keybindActions.first { $0.name == draftAction }?.argument.values
    }

    // MARK: - Bindings model

    struct Binding: Identifiable {
        let id = UUID()
        var trigger: String
        var action: String
        var raw: String
    }

    private var bindings: [Binding] {
        SettingsValueText.lines(model.currentText(for: option)).compactMap { line in
            guard let value = SettingsValueText.parse(line: line, expectedKey: option.name),
                  !value.isEmpty
            else { return nil }
            // Split at the LAST '=' to keep chained triggers like a>b intact.
            guard let eq = value.lastIndex(of: "=") else { return nil }
            let trigger = String(value[..<eq]).trimmingCharacters(in: .whitespaces)
            let action = String(value[value.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            return Binding(trigger: trigger, action: action, raw: value)
        }
    }

    // MARK: - Mutations

    private func addDraft() {
        let action = actionText()
        let raw = "\(draftTrigger)=\(action)"
        var updated = bindings.map { $0.raw }
        updated.append(raw)
        draftTrigger = ""
        draftArg = ""
        save(updated)
    }

    private func removeSelected() {
        guard let idx = selection else { return }
        var updated = bindings.map { $0.raw }
        guard idx < updated.count else { return }
        updated.remove(at: idx)
        selection = nil
        save(updated)
    }

    private func actionText() -> String {
        switch actionArgumentKind {
        case .none: return draftAction
        default:
            let arg = draftArg.trimmingCharacters(in: .whitespaces)
            return arg.isEmpty ? draftAction : "\(draftAction):\(arg)"
        }
    }

    private func save(_ raws: [String]) {
        if raws.isEmpty {
            model.reset(option)
        } else {
            model.setValue(option, valueText: SettingsValueText.format(key: option.name, values: raws))
        }
    }
}

/// Small "Record" button that captures the next key press and
/// writes it into the trigger field using Ghostty's config syntax.
struct KeybindRecorderButton: View {
    @SwiftUI.Binding var trigger: String
    @State private var recording: Bool = false

    var body: some View {
        Button(recording ? "Press keys…" : "Record") {
            recording.toggle()
        }
        .background(
            KeybindRecorderView(recording: $recording, trigger: $trigger)
                .frame(width: 0, height: 0)
        )
    }
}

private struct KeybindRecorderView: NSViewRepresentable {
    @SwiftUI.Binding var recording: Bool
    @SwiftUI.Binding var trigger: String

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCapture = { captured in
            trigger = captured
            recording = false
        }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.recording = recording
        if recording { DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) } }
    }
}

private final class RecorderNSView: NSView {
    var recording: Bool = false
    var onCapture: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { recording }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("alt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        if let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty {
            parts.append(key)
        }
        onCapture?(parts.joined(separator: "+"))
    }
}
