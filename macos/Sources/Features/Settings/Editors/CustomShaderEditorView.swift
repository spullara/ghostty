import SwiftUI
import UniformTypeIdentifiers

/// Ordered file list for repeatable-path options like
/// `custom-shader`. Users add files via NSOpenPanel, remove or
/// reorder entries, and each row emits a single `key = <path>` line.
struct CustomShaderEditorView: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    @State private var selection: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Shader files").font(.headline)
                Spacer()
                Button {
                    addFiles()
                } label: {
                    Label("Add…", systemImage: "plus")
                }
                Button {
                    removeSelected()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selection == nil)
            }
            .padding()

            Divider()

            List(selection: $selection) {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .tag(path)
                }
                .onMove { indices, newOffset in
                    var updated = paths
                    updated.move(fromOffsets: indices, toOffset: newOffset)
                    save(updated)
                }
            }
            .listStyle(.plain)

            if paths.isEmpty {
                VStack {
                    Text("No shaders configured")
                        .foregroundStyle(.secondary)
                    Button("Add shader file…") { addFiles() }
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    // MARK: - Data

    private var paths: [String] {
        let text = model.currentText(for: option)
        return SettingsValueText.lines(text).compactMap { line in
            SettingsValueText.parse(line: line, expectedKey: option.name)
        }.filter { !$0.isEmpty }
    }

    // MARK: - Mutations

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "glsl") ?? .data,
            UTType(filenameExtension: "hlsl") ?? .data,
            UTType(filenameExtension: "wgsl") ?? .data,
            UTType(filenameExtension: "metal") ?? .data,
            .data,
        ]
        guard panel.runModal() == .OK else { return }
        var updated = paths
        for url in panel.urls {
            let p = url.path
            if !updated.contains(p) { updated.append(p) }
        }
        save(updated)
    }

    private func removeSelected() {
        guard let sel = selection else { return }
        var updated = paths
        updated.removeAll { $0 == sel }
        selection = nil
        save(updated)
    }

    private func save(_ values: [String]) {
        if values.isEmpty {
            model.reset(option)
        } else {
            model.setValue(option, valueText: SettingsValueText.format(key: option.name, values: values))
        }
    }
}
