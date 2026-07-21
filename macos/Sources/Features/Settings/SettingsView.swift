import SwiftUI

/// The root Settings window content. If the schema failed to load
/// (missing bundle resource, decoder mismatch), falls back to the
/// placeholder view so the app is still usable.
struct SettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        if let schema = SettingsSchema.shared {
            SettingsRootView(model: appDelegate.settingsViewModel(schema: schema))
        } else {
            SettingsPlaceholderView()
        }
    }
}

/// Two-column layout: category sidebar + option list, with a
/// diagnostics bar pinned to the bottom.
struct SettingsRootView: View {
    @ObservedObject var model: SettingsViewModel
    @EnvironmentObject private var appDelegate: AppDelegate
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
                    .frame(minWidth: 560, minHeight: 500)
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 820, minHeight: 560)

            if !model.diagnostics.isEmpty {
                DiagnosticsBar(diagnostics: model.diagnostics)
            }
        }
    }

    /// Fixed sidebar width sized to fit the longest label
    /// ("Configuration File" / "Appearance & Theme") plus the icon
    /// and section-header padding. Kept constant so the divider is
    /// not user-draggable.
    private static let sidebarWidth: CGFloat = 220

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $model.selectedItem) {
            Section("Settings") {
                ForEach(SettingsCategory.allCases) { cat in
                    Label(cat.title, systemImage: cat.systemImage)
                        .tag(SettingsSidebarItem.category(cat))
                }
            }
            Section("Advanced") {
                Label(
                    SettingsSidebarItem.configFile.title,
                    systemImage: SettingsSidebarItem.configFile.systemImage
                )
                .tag(SettingsSidebarItem.configFile)
            }
        }
        .navigationTitle("Settings")
        .navigationSplitViewColumnWidth(
            min: Self.sidebarWidth,
            ideal: Self.sidebarWidth,
            max: Self.sidebarWidth
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedItem {
        case .category:
            SettingsCategoryDetail(model: model, searchFocused: $searchFocused)
        case .configFile:
            ConfigFilePaneView(model: model, ghostty: appDelegate.ghostty)
        }
    }
}

/// Right-hand pane: category title + search bar + scrolling list.
struct SettingsCategoryDetail: View {
    @ObservedObject var model: SettingsViewModel
    var searchFocused: FocusState<Bool>.Binding

    @State private var showResetConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(currentCategory?.title ?? "").font(.title2).fontWeight(.semibold)
                Spacer()
                if let cat = currentCategory, !model.overriddenOptions(in: cat).isEmpty {
                    Button("Reset all in category…") { showResetConfirm = true }
                }
            }
            .padding([.horizontal, .top])

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search settings", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                    .focused(searchFocused)
                if !model.search.isEmpty {
                    Button {
                        model.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                // Hidden button that binds Cmd+F to focus the search field.
                Button("Focus Search") { searchFocused.wrappedValue = true }
                    .keyboardShortcut("f", modifiers: [.command])
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let options = model.visibleOptions
                    if options.isEmpty {
                        Text("No settings match your search.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(options) { option in
                            SettingRow(option: option, model: model)
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .confirmationDialog(
            "Reset all overrides in \(currentCategory?.title ?? "")?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                if let cat = currentCategory { model.resetCategory(cat) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears every overlay entry in this category. Values set in your primary config file are unaffected.")
        }
    }

    private var currentCategory: SettingsCategory? {
        if case .category(let c) = model.selectedItem { return c }
        return nil
    }
}

/// Bottom bar surfacing config diagnostics (parse errors, invalid
/// values) from the most recent load.
struct DiagnosticsBar: View {
    let diagnostics: [String]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(diagnostics.count) configuration issue\(diagnostics.count == 1 ? "" : "s")")
                        .font(.callout).fontWeight(.medium)
                    ForEach(diagnostics.prefix(3), id: \.self) { msg in
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                    if diagnostics.count > 3 {
                        Text("… and \(diagnostics.count - 3) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(Color.yellow.opacity(0.1))
        }
    }
}

/// Fallback shown when the schema JSON is missing or malformed.
struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings unavailable").font(.title2)
            Text("The Settings schema could not be loaded from this build. " +
                 "Please rebuild Ghostty from a clean tree and try again.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 200)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPlaceholderView()
    }
}
