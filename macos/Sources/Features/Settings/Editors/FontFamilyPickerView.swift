import AppKit
import SwiftUI

/// Ordered fallback font family list. Backing string is a
/// repeatable-string kind (`font-family = ...` per entry). Users pick
/// families from the system list (optionally filtered to
/// monospaced) or type any name manually.
struct FontFamilyPickerView: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    @State private var selectedFallback: String? = nil
    @State private var monospacedOnly: Bool = true
    @State private var search: String = ""

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Fallback order").font(.headline)
                    Spacer()
                    Button {
                        removeSelected()
                    } label: { Label("Remove", systemImage: "minus") }
                        .disabled(selectedFallback == nil)
                }
                .padding()
                Divider()
                List(selection: $selectedFallback) {
                    ForEach(families, id: \.self) { family in
                        Text(family)
                            .font(.custom(family, size: NSFont.systemFontSize))
                            .tag(family)
                    }
                    .onMove { indices, newOffset in
                        var updated = families
                        updated.move(fromOffsets: indices, toOffset: newOffset)
                        save(updated)
                    }
                }
                if families.isEmpty {
                    Text("No families configured; add one from the list on the right.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .frame(minWidth: 260)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Toggle("Monospaced only", isOn: $monospacedOnly)
                    Spacer()
                }
                .padding()
                TextField("Search families…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                Divider().padding(.top, 8)
                List(filteredAvailable, id: \.self) { name in
                    HStack {
                        Text(name).font(.custom(name, size: NSFont.systemFontSize))
                        Spacer()
                        Button("Add") { add(name) }
                    }
                }
            }
            .frame(minWidth: 260)
        }
    }

    // MARK: - Data

    private var families: [String] {
        SettingsValueText.lines(model.currentText(for: option)).compactMap {
            SettingsValueText.parse(line: $0, expectedKey: option.name)
        }.filter { !$0.isEmpty }
    }

    private var allAvailable: [String] {
        Self.availableFamilies(monospacedOnly: monospacedOnly)
    }

    private var filteredAvailable: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return allAvailable }
        return allAvailable.filter { $0.lowercased().contains(q) }
    }

    /// Cached lookup: NSFontManager is slow enough that we memoize
    /// per monospaced/all bucket for the lifetime of the process.
    private static var cache: [Bool: [String]] = [:]

    static func availableFamilies(monospacedOnly: Bool) -> [String] {
        if let cached = cache[monospacedOnly] { return cached }
        let all = NSFontManager.shared.availableFontFamilies.sorted { $0.lowercased() < $1.lowercased() }
        let result: [String]
        if monospacedOnly {
            result = all.filter { family in
                guard let font = NSFont(name: family, size: NSFont.systemFontSize) else { return false }
                return font.isFixedPitch
            }
        } else {
            result = all
        }
        cache[monospacedOnly] = result
        return result
    }

    // MARK: - Mutations

    private func add(_ family: String) {
        var updated = families
        if !updated.contains(family) { updated.append(family) }
        save(updated)
    }

    private func removeSelected() {
        guard let sel = selectedFallback else { return }
        var updated = families
        updated.removeAll { $0 == sel }
        selectedFallback = nil
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
