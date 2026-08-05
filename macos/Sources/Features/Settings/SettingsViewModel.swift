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

    /// Normalized query string; empty means "no active search".
    var activeQuery: String {
        search.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The rows shown in the detail pane when the user is on a
    /// specific category and not searching globally.
    var visibleOptions: [SettingsSchema.Option] {
        guard case .category(let category) = selectedItem else { return [] }
        let base = optionsByCategory[category] ?? []
        let query = activeQuery
        guard !query.isEmpty else { return base }
        return Self.rank(options: base, query: query)
    }

    /// Global search results grouped by category, used when the
    /// search field has text. Each category with at least one hit
    /// appears in display order; hits within a category are ranked
    /// name-prefix > substring > docs-only.
    var globalSearchResults: [(SettingsCategory, [SettingsSchema.Option])] {
        let query = activeQuery
        guard !query.isEmpty else { return [] }
        var out: [(SettingsCategory, [SettingsSchema.Option])] = []
        for category in SettingsCategory.allCases {
            let base = optionsByCategory[category] ?? []
            let hits = Self.rank(options: base, query: query)
            if !hits.isEmpty { out.append((category, hits)) }
        }
        return out
    }

    private static func rank(
        options: [SettingsSchema.Option],
        query: String
    ) -> [SettingsSchema.Option] {
        let matches = options.compactMap { opt -> (SettingsSchema.Option, Int)? in
            let name = opt.name.lowercased()
            let display = opt.displayName.lowercased()
            if name.hasPrefix(query) || display.hasPrefix(query) { return (opt, 0) }
            if name.contains(query) || display.contains(query) { return (opt, 1) }
            if opt.docs.lowercased().contains(query) { return (opt, 2) }
            return nil
        }
        return matches.sorted { $0.1 < $1.1 }.map { $0.0 }
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
        for name in names {
            overlay.remove(name)
            if Self.isSurfaceOnly(name) { pendingSurfaceOnlyChanges.insert(name) }
        }
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
        // No-op if the write would leave state unchanged. SwiftUI
        // controls with two-way bindings can call the setter with
        // the same value during view updates; without this guard
        // that would falsely flag the option as dirty.
        let previous = overlay.entries[option.name]
        if previous == valueText { return }
        let effective = effectiveValues[option.name] ?? option.default
        if previous == nil && valueText == effective { return }
        overlay.set(option.name, valueText: valueText)
        noteChanged(option)
        onOverlayChange?()
    }

    /// Drop the overlay entry for this option, restoring the primary
    /// config file's (or default) value. No-op if the option wasn't
    /// overridden — avoids falsely flagging a restart hint when the
    /// user clicks the reset arrow on a row they hadn't changed.
    func reset(_ option: SettingsSchema.Option) {
        guard overlay.entries[option.name] != nil else { return }
        overlay.remove(option.name)
        noteChanged(option)
        onOverlayChange?()
    }

    /// Invoked after any overlay mutation. Wired by the app delegate
    /// to request a `Ghostty.App.reloadConfig()`.
    var onOverlayChange: (() -> Void)?

    /// Invoked when the user asks the app to open a fresh terminal
    /// window (so surface-only settings can take effect). Wired by
    /// the app delegate.
    var onRequestNewWindow: (() -> Void)?

    /// Names of options touched since the last time the settings
    /// window opened. Used to drive the "changes need a new window"
    /// banner. Cleared explicitly by ``acknowledgeRestartHint()``.
    @Published private(set) var pendingSurfaceOnlyChanges: Set<String> = []

    /// Settings that only take effect on new surfaces (terminals /
    /// windows) — reloading the running config cannot swap these
    /// under a live shell.
    static let surfaceOnlyOptions: Set<String> = [
        "command",
        "initial-command",
        "working-directory",
        "wait-after-command",
        "abnormal-command-exit-runtime",
        "term",
        "env",
        "shell-integration",
        "shell-integration-features",
        "enquiry-response",
        "class",
        "x11-instance-name",
        "background-blur",
        "quit-after-last-window-closed",
        "quit-after-last-window-closed-delay",
        "initial-window",
        "fullscreen",
        "maximize",
        "window-height",
        "window-width",
        "window-position-x",
        "window-position-y",
        "window-save-state",
        "macos-titlebar-style",
        "macos-titlebar-proxy-icon",
        "macos-window-shadow",
        "macos-non-native-fullscreen",
    ]

    /// True if the given option requires a new terminal/window to
    /// take effect after being changed.
    static func isSurfaceOnly(_ name: String) -> Bool {
        surfaceOnlyOptions.contains(name)
    }

    /// Record that the given option was just changed, so the UI can
    /// prompt the user to open a new window when appropriate.
    func noteChanged(_ option: SettingsSchema.Option) {
        if Self.isSurfaceOnly(option.name) {
            pendingSurfaceOnlyChanges.insert(option.name)
        }
    }

    /// Clear the pending-changes set (e.g. after the user opens a new
    /// window from the banner).
    func acknowledgeRestartHint() {
        pendingSurfaceOnlyChanges.removeAll()
    }
}
