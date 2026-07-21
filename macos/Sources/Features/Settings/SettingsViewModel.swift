import Combine
import Foundation
import GhosttyKit
import SwiftUI

/// State backing the Settings window.
///
/// Owns the loaded schema, the overlay store, the effective value
/// text for every option, and the currently-selected category /
/// search filter. Re-fetches effective values whenever the app posts
/// `ghosttyConfigDidChange` so the UI always mirrors the running
/// config.
@MainActor
final class SettingsViewModel: ObservableObject {
    let schema: SettingsSchema
    let overlay: OverlayConfigStore

    /// Search box text (matches option names + docs).
    @Published var search: String = ""

    /// Currently-selected sidebar row.
    @Published var selectedItem: SettingsSidebarItem = .category(.font)

    /// Diagnostics from the most recent config load, surfaced in the
    /// window's bottom bar. Empty when the running config is clean.
    @Published private(set) var diagnostics: [String] = []

    /// Canonical config-file text (`key = ...\n`) for every option in
    /// the loaded config. Updated whenever the config reloads.
    @Published private(set) var effectiveValues: [String: String] = [:]

    private var configObserver: NSObjectProtocol?

    /// Options grouped by category, computed once from the schema.
    let optionsByCategory: [SettingsCategory: [SettingsSchema.Option]]

    init(schema: SettingsSchema, overlay: OverlayConfigStore = .shared) {
        self.schema = schema
        self.overlay = overlay

        var grouped: [SettingsCategory: [SettingsSchema.Option]] = [:]
        for option in schema.options {
            let cat = SettingsCategory.category(for: option.name)
            grouped[cat, default: []].append(option)
        }
        self.optionsByCategory = grouped

        self.configObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let config = note.userInfo?[
                SwiftUI.Notification.Name.GhosttyConfigChangeKey
            ] as? Ghostty.Config
            guard let self, let config else { return }
            MainActor.assumeIsolated {
                self.refreshEffectiveValues(config: config)
                self.diagnostics = config.errors
            }
        }
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Copy the diagnostics list from the given config into the
    /// published `diagnostics` array so the window's bottom bar
    /// updates on demand (used when the settings window opens before
    /// the first reload notification).
    func updateDiagnostics(from config: Ghostty.Config) {
        self.diagnostics = config.errors
    }

    /// Pull the current text for every schema option from the given
    /// live config via `ghostty_config_get_value_text`.
    func refreshEffectiveValues(config: Ghostty.Config) {
        guard let cfg = config.config else { return }
        var values: [String: String] = [:]
        values.reserveCapacity(schema.options.count)
        for option in schema.options {
            let name = option.name
            let text = name.withCString { ptr -> String in
                let raw = ghostty_config_get_value_text(
                    cfg, ptr, UInt(name.utf8.count)
                )
                return Ghostty.AllocatedString(raw).string
            }
            values[name] = text
        }
        self.effectiveValues = values
    }

    /// The rows shown in the detail pane, respecting the sidebar
    /// selection and search box. Ranks name-prefix matches above
    /// substring matches so exact hits float to the top.
    var visibleOptions: [SettingsSchema.Option] {
        guard case .category(let category) = selectedItem else { return [] }
        let base = optionsByCategory[category] ?? []
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return base }
        let matches = base.compactMap { opt -> (SettingsSchema.Option, Int)? in
            let name = opt.name.lowercased()
            if name.hasPrefix(query) { return (opt, 0) }
            if name.contains(query) { return (opt, 1) }
            if opt.docs.lowercased().contains(query) { return (opt, 2) }
            return nil
        }
        return matches
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    /// Every option that currently has an overlay entry in the given
    /// category. Used by "Reset all" affordances.
    func overriddenOptions(in category: SettingsCategory) -> [SettingsSchema.Option] {
        (optionsByCategory[category] ?? []).filter { isOverridden($0) }
    }

    /// Bulk-clear every overlay entry in the given category. The
    /// caller should confirm with the user before invoking.
    func resetCategory(_ category: SettingsCategory) {
        let names = overriddenOptions(in: category).map(\.name)
        guard !names.isEmpty else { return }
        for name in names { overlay.remove(name) }
        onOverlayChange?()
    }

    /// True when the option has an entry in the overlay file.
    func isOverridden(_ option: SettingsSchema.Option) -> Bool {
        overlay.entries[option.name] != nil
    }

    /// The text the UI should display for the given option. Prefers
    /// the overlay (since it's what the GUI last wrote) and falls
    /// back to the current effective value.
    func currentText(for option: SettingsSchema.Option) -> String {
        overlay.entries[option.name] ?? effectiveValues[option.name] ?? option.default
    }

    /// Write a new value for the given option to the overlay. The
    /// caller is responsible for formatting `valueText` as canonical
    /// config-file text (`"key = value\n"`, possibly multiple lines).
    /// Requests a config reload so the running app picks up the new
    /// value and the UI's `effectiveValues` map refreshes.
    func setValue(_ option: SettingsSchema.Option, valueText: String) {
        overlay.set(option.name, valueText: valueText)
        onOverlayChange?()
    }

    /// Drop the overlay entry for this option, restoring the primary
    /// config file's (or default) value.
    func reset(_ option: SettingsSchema.Option) {
        overlay.remove(option.name)
        onOverlayChange?()
    }

    /// Invoked after any overlay mutation. Wired by the app delegate
    /// to request a `Ghostty.App.reloadConfig()`.
    var onOverlayChange: (() -> Void)?
}
