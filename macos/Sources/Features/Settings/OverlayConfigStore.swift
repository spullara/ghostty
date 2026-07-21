import Foundation
import OSLog

/// A file-backed store for settings written by the GUI.
///
/// The GUI never mutates the user's primary `config.ghostty` file.
/// Instead it writes to a sibling file `settings-ui.ghostty` in the
/// same directory. That file is loaded *last* by
/// ``Ghostty.Config.loadConfig`` so its values always win — matching
/// the plan's GUI-wins policy.
///
/// Each entry is a single logical setting whose text value is the
/// canonical form produced by `ghostty_config_get_value_text`
/// (possibly multiple `key = ...` lines for repeatable options). We
/// only track which keys the GUI is overriding; unset keys fall
/// through to the user's `config.ghostty` (or defaults).
final class OverlayConfigStore: ObservableObject {
    /// Shared instance used both by the Settings UI and by
    /// ``Ghostty.Config.loadConfig`` so both sides see the same
    /// entries without threading through the app delegate.
    static let shared = OverlayConfigStore()

    /// Per-key text as it will be written to the overlay file. The
    /// value must already be in canonical config-file form (i.e.
    /// end with a newline; multi-line for repeatable types).
    @Published private(set) var entries: [String: String] = [:]

    /// Absolute path to the overlay file. Resolved lazily on first
    /// access so tests can stub it.
    let url: URL

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "OverlayConfigStore"
    )

    /// Header written at the top of the overlay file so users who
    /// stumble across it understand where it comes from.
    private static let header = """
        # This file is managed by Ghostty's Settings window. Values
        # here override the corresponding entries in your main
        # config.ghostty. Delete a line to fall back to the default
        # (or your primary config file).

        """

    init(url: URL = OverlayConfigStore.defaultURL()) {
        self.url = url
        self.entries = Self.parse(url: url)
    }

    /// The default overlay path, matching Ghostty's own default
    /// primary config location on macOS
    /// (`~/Library/Application Support/com.mitchellh.ghostty/settings-ui.ghostty`).
    static func defaultURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)
            .appendingPathComponent("settings-ui.ghostty", isDirectory: false)
    }

    /// Set the canonical text for `key`. Value must be the exact
    /// output of `ghostty_config_get_value_text` (already includes
    /// the trailing newline and any repeated `key = ...` lines).
    func set(_ key: String, valueText: String) {
        entries[key] = valueText
        persist()
    }

    /// Remove any override for `key`, restoring the value from the
    /// user's primary config (or the built-in default).
    func remove(_ key: String) {
        guard entries.removeValue(forKey: key) != nil else { return }
        persist()
    }

    /// Drop all overrides. Primarily useful for a "reset all"
    /// affordance and tests.
    func removeAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        persist()
    }

    // MARK: - I/O

    /// Return the overlay contents as canonical config text, filtered
    /// through our parser so malformed lines (missing `=`, empty key)
    /// are dropped before Zig sees them. This keeps hand-editing the
    /// overlay file forgiving without polluting the diagnostics bar
    /// with our own noise. Used by ``Ghostty.Config.loadConfig``.
    func loadText() -> String {
        let parsed = Self.parse(url: url)
        return Self.serialize(entries: parsed)
    }

    /// Serialize `entries` and write to disk. Best-effort: I/O
    /// failures are logged but not thrown, since the UI has no useful
    /// recovery.
    private func persist() {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            let body = Self.header + Self.serialize(entries: entries)
            try body.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            Self.logger.error(
                "failed to write overlay file at \(self.url.path, privacy: .public): \(error, privacy: .public)"
            )
        }
    }

    /// Deterministic serialization: keys sorted alphabetically so
    /// diffs stay stable. Values are already canonical text and end
    /// with a newline.
    static func serialize(entries: [String: String]) -> String {
        var out = ""
        for key in entries.keys.sorted() {
            let text = entries[key] ?? ""
            out += text
            if !text.hasSuffix("\n") { out += "\n" }
        }
        return out
    }

    /// Parse an overlay file back into `[key: canonical text]`. We
    /// intentionally do a minimal line-oriented parse here — Zig's
    /// config loader is authoritative for actual value validation;
    /// this only needs to reproduce what we wrote so the GUI can
    /// tell which keys are overridden.
    static func parse(url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return [:]
        }
        var out: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let entry = line + "\n"
            if var existing = out[key] {
                existing += entry
                out[key] = existing
            } else {
                out[key] = entry
            }
        }
        return out
    }
}
