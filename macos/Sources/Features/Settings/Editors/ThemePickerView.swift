import SwiftUI

/// Picker for the `theme` option. Enumerates bundled themes from
/// `Bundle.main.resourceURL/ghostty/themes` plus user themes at
/// `~/.config/ghostty/themes`, previews their background/foreground
/// swatches, and supports both single (`theme = X`) and split
/// (`theme = light:X,dark:Y`) forms.
struct ThemePickerView: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel

    enum Mode: Hashable { case single, splitLightDark }
    @State private var mode: Mode = .single
    @State private var search: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $mode) {
                Text("Single").tag(Mode.single)
                Text("Split light/dark").tag(Mode.splitLightDark)
            }
            .pickerStyle(.segmented)
            .onAppear { mode = detectMode() }
            .padding(.horizontal)

            TextField("Search themes…", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            switch mode {
            case .single:
                singleView
            case .splitLightDark:
                splitView
            }
        }
        .padding(.vertical)
    }

    @ViewBuilder
    private var singleView: some View {
        let selected = currentValue()
        List(filteredThemes, id: \.name, selection: Binding(
            get: { selected },
            set: { newValue in
                if let name = newValue { save("\(name)") }
            }
        )) { theme in
            themeRow(theme: theme).tag(theme.name)
        }
    }

    @ViewBuilder
    private var splitView: some View {
        let parts = parseSplit(currentValue() ?? "")
        HSplitView {
            VStack(alignment: .leading) {
                Text("Light").font(.headline).padding(.horizontal)
                List(filteredThemes, id: \.name, selection: Binding(
                    get: { parts.light },
                    set: { save("light:\($0 ?? ""),dark:\(parts.dark ?? "")") }
                )) { theme in themeRow(theme: theme).tag(theme.name) }
            }
            VStack(alignment: .leading) {
                Text("Dark").font(.headline).padding(.horizontal)
                List(filteredThemes, id: \.name, selection: Binding(
                    get: { parts.dark },
                    set: { save("light:\(parts.light ?? ""),dark:\($0 ?? "")") }
                )) { theme in themeRow(theme: theme).tag(theme.name) }
            }
        }
    }

    @ViewBuilder
    private func themeRow(theme: Theme) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.background ?? .gray)
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
            Text(theme.name).font(.system(.body, design: .monospaced))
            Spacer()
            HStack(spacing: 2) {
                ForEach(0..<min(8, theme.paletteSample.count), id: \.self) { i in
                    Rectangle().fill(theme.paletteSample[i]).frame(width: 8, height: 12)
                }
            }
        }
    }

    // MARK: - Data

    struct Theme: Identifiable {
        var id: String { name }
        let name: String
        let background: Color?
        let foreground: Color?
        let paletteSample: [Color]
    }

    private var themes: [Theme] { ThemePickerView.loadThemes() }

    private var filteredThemes: [Theme] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return themes }
        return themes.filter { $0.name.lowercased().contains(q) }
    }

    private func currentValue() -> String? {
        let text = model.currentText(for: option)
        let v = SettingsValueText.value(for: option.name, in: text)
        return v.isEmpty ? nil : v
    }

    private func detectMode() -> Mode {
        guard let v = currentValue() else { return .single }
        return v.contains("light:") && v.contains("dark:") ? .splitLightDark : .single
    }

    private func parseSplit(_ value: String) -> (light: String?, dark: String?) {
        var light: String? = nil
        var dark: String? = nil
        for token in value.split(separator: ",") {
            let t = token.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("light:") { light = String(t.dropFirst("light:".count)) }
            if t.hasPrefix("dark:") { dark = String(t.dropFirst("dark:".count)) }
        }
        return (light, dark)
    }

    private func save(_ value: String) {
        if value.isEmpty {
            model.reset(option)
        } else {
            model.setValue(option, valueText: SettingsValueText.format(key: option.name, value: value))
        }
    }

    // MARK: - Theme loading

    /// Scan bundled + user theme directories. User themes shadow
    /// bundled themes with the same name (matches `src/config/theme.zig`).
    static func loadThemes() -> [Theme] {
        var byName: [String: Theme] = [:]
        for dir in themeDirectories() {
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in items {
                let url = dir.appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                if let theme = parseTheme(name: name, url: url) {
                    byName[theme.name] = theme
                }
            }
        }
        return byName.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private static func themeDirectories() -> [URL] {
        var dirs: [URL] = []
        // User themes take precedence.
        let home = FileManager.default.homeDirectoryForCurrentUser
        dirs.append(home.appendingPathComponent(".config/ghostty/themes"))
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("ghostty/themes"))
        }
        return dirs
    }

    private static func parseTheme(name: String, url: URL) -> Theme? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var background: Color? = nil
        var foreground: Color? = nil
        var palette: [Color] = Array(repeating: Color.clear, count: 16)
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key == "background" { background = ColorSettingControl.color(from: value) }
            else if key == "foreground" { foreground = ColorSettingControl.color(from: value) }
            else if key == "palette" {
                let parts = value.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let idx = Int(String(parts[0])),
                   idx >= 0, idx < 16,
                   let c = ColorSettingControl.color(from: String(parts[1])) {
                    palette[idx] = c
                }
            }
        }
        return Theme(name: name, background: background, foreground: foreground,
                     paletteSample: palette)
    }
}
