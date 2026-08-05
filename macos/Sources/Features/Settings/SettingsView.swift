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
            SettingsSearchBar(
                text: $model.search,
                focused: $searchFocused
            )
            Divider()

            NavigationSplitView {
                sidebar
            } detail: {
                detail
                    .frame(minWidth: 560, minHeight: 500)
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 820, minHeight: 560)

            if !model.pendingSurfaceOnlyChanges.isEmpty {
                RestartHintBar(model: model)
            }

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
        if !model.activeQuery.isEmpty {
            SettingsSearchResultsView(model: model)
        } else {
            switch model.selectedItem {
            case .category:
                SettingsCategoryDetail(model: model)
            case .configFile:
                ConfigFilePaneView(model: model, ghostty: appDelegate.ghostty)
            }
        }
    }
}

/// Persistent search bar shown at the top of the Settings window so
/// it's reachable from every pane (including the Configuration File
/// editor). Typing here switches the detail pane to a global
/// results view that spans every category.
struct SettingsSearchBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search all settings", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused(focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
            // Hidden button that binds Cmd+F to focus the search field.
            Button("Focus Search") { focused.wrappedValue = true }
                .keyboardShortcut("f", modifiers: [.command])
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Detail pane shown when the search field has text. Groups the hits
/// by category so users can see where each option lives; category
/// headers are click-through so they can jump straight to that
/// category's full list.
struct SettingsSearchResultsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        let groups = model.globalSearchResults
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Search results for \u{201C}\(model.search)\u{201D}")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                let total = groups.reduce(0) { $0 + $1.1.count }
                Text("\(total) match\(total == 1 ? "" : "es")")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding([.horizontal, .top])

            Divider().padding(.top, 8)

            if groups.isEmpty {
                VStack(spacing: 8) {
                    Text("No settings match your search.")
                        .foregroundStyle(.secondary)
                    Button("Clear search") { model.search = "" }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.0) { (cat, options) in
                            Button {
                                model.selectedItem = .category(cat)
                                model.search = ""
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: cat.systemImage)
                                        .foregroundStyle(.secondary)
                                    Text(cat.title).font(.headline)
                                    Text("(\(options.count))")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                        .font(.caption)
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .help("Jump to \(cat.title)")
                            Divider()
                            ForEach(options) { option in
                                SettingRow(option: option, model: model)
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// Right-hand pane: category title + scrolling list of options.
struct SettingsCategoryDetail: View {
    @ObservedObject var model: SettingsViewModel

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

            Divider().padding(.top, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let options = model.visibleOptions
                    if options.isEmpty {
                        Text("This category is empty.")
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

/// Bottom bar shown when the user has changed one or more settings
/// that only take effect for new terminals/windows. Offers a button
/// that opens a fresh terminal so the change becomes visible without
/// the user having to quit the app.
struct RestartHintBar: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    let count = model.pendingSurfaceOnlyChanges.count
                    Text("\(count) change\(count == 1 ? "" : "s") need a new terminal")
                        .font(.callout).fontWeight(.medium)
                    Text(model.pendingSurfaceOnlyChanges.sorted().joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.tail)
                }
                Spacer()
                Button("Dismiss") { model.acknowledgeRestartHint() }
                Button("Open New Window") {
                    model.onRequestNewWindow?()
                    model.acknowledgeRestartHint()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(8)
            .background(Color.blue.opacity(0.08))
        }
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
