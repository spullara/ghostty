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
/// Each entry block is a single logical setting whose text value is the
/// canonical form produced by `ghostty_config_get_value_text`
/// (possibly multiple `key = ...` lines for repeatable options). We
/// only track which keys the GUI is overriding; unset keys fall
/// through to the user's `config.ghostty` (or defaults).
final class OverlayConfigStore: ObservableObject {
    /// A line-preserving representation of the overlay file.
    enum Block: Equatable {
        case entry(key: String, text: String)
        case comment(text: String)
        case blank
    }

    /// Shared instance used both by the Settings UI and by
    /// ``Ghostty.Config.loadConfig`` so both sides see the same
    /// entries without threading through the app delegate.
    static let shared = OverlayConfigStore()

    /// File blocks as they will be written to the overlay file. Entry
    /// values must already be in canonical config-file form (i.e. end
    /// with a newline; multi-line for repeatable types).
    @Published private(set) var blocks: [Block] = []

    /// Whether the on-disk file ended with a trailing newline. Preserved
    /// so that a parse/serialize round-trip is byte-exact for
    /// hand-edited files that omit the final newline. New files written
    /// by ``persist()`` always include the trailing newline.
    private var hasTrailingNewline: Bool = true

    /// Per-key text grouped for callers that need the old dictionary
    /// interface. Repeatable keys are concatenated in file order.
    var entries: [String: String] {
        var out: [String: String] = [:]
        for block in blocks {
            guard case let .entry(key, text) = block else { continue }
            out[key, default: ""] += text
        }
        return out
    }

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
        let parsed = Self.parseFile(url: url)
        self.blocks = parsed.blocks
        self.hasTrailingNewline = parsed.hasTrailingNewline
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
        var didReplace = false
        var next: [Block] = []
        for block in blocks {
            guard case let .entry(existingKey, _) = block, existingKey == key else {
                next.append(block)
                continue
            }

            if !didReplace, !valueText.isEmpty {
                next.append(.entry(key: key, text: valueText))
            }
            didReplace = true
        }

        if !didReplace, !valueText.isEmpty {
            next.append(.entry(key: key, text: valueText))
        }

        guard next != blocks else { return }
        blocks = next
        persist()
    }

    /// Remove any override for `key`, restoring the value from the
    /// user's primary config (or the built-in default).
    func remove(_ key: String) {
        let next = blocks.filter { block in
            guard case let .entry(existingKey, _) = block else { return true }
            return existingKey != key
        }
        guard next.count != blocks.count else { return }
        blocks = next
        persist()
    }

    /// Drop all overrides. Primarily useful for a "reset all"
    /// affordance and tests.
    func removeAll() {
        let next = blocks.filter { block in
            guard case .entry = block else { return true }
            return false
        }
        guard next.count != blocks.count else { return }
        blocks = next
        persist()
    }

    // MARK: - I/O

    /// Return the overlay contents as canonical config text, filtered
    /// through our parser so malformed lines (missing `=`, empty key)
    /// are dropped before Zig sees them. This keeps hand-editing the
    /// overlay file forgiving without polluting the diagnostics bar
    /// with our own noise. Used by ``Ghostty.Config.loadConfig``.
    func loadText() -> String {
        let parsed = Self.parseFile(url: url)
        return Self.serialize(
            entries: parsed.blocks,
            trailingNewline: parsed.hasTrailingNewline
        )
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
            // Any GUI-driven write normalizes to a trailing newline so
            // the file stays well-formed even if it was hand-edited
            // without one previously.
            hasTrailingNewline = true
            let body = Self.bodyWithHeader(for: blocks)
            try body.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            Self.logger.error(
                "failed to write overlay file at \(self.url.path, privacy: .public): \(error, privacy: .public)"
            )
        }
    }

    /// Serialize blocks in file order. Entry values are already
    /// canonical text and should end with a newline. Pass
    /// `trailingNewline: false` to reproduce a source file whose last
    /// line lacked a newline (used by ``loadText`` to preserve
    /// hand-edited files byte-for-byte).
    static func serialize(
        entries blocks: [Block],
        trailingNewline: Bool = true
    ) -> String {
        var out = ""
        for block in blocks {
            switch block {
            case let .entry(_, text):
                out += text
                if !text.hasSuffix("\n") { out += "\n" }
            case let .comment(text):
                out += text
                if !text.hasSuffix("\n") { out += "\n" }
            case .blank:
                out += "\n"
            }
        }
        if !trailingNewline, out.hasSuffix("\n") {
            out.removeLast()
        }
        return out
    }

    /// Include Ghostty's managed-file header unless the file already
    /// starts with it. This avoids duplicating the header on every save.
    private static func bodyWithHeader(for blocks: [Block]) -> String {
        let text = Self.serialize(entries: blocks)
        guard !text.hasPrefix(Self.header) else { return text }
        return Self.header + text
    }

    /// Read and parse an overlay file, returning both the block list
    /// and whether the on-disk file ended with a trailing newline. The
    /// latter is preserved so ``loadText`` can round-trip hand-edited
    /// files that omit the final newline.
    static func parseFile(url: URL) -> (blocks: [Block], hasTrailingNewline: Bool) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return ([], true)
        }
        return (parse(text: text), text.isEmpty || text.hasSuffix("\n"))
    }

    /// Parse overlay text into blocks. We intentionally do a minimal
    /// line-oriented parse here — Zig's config loader is authoritative
    /// for actual value validation; this only needs to reproduce valid
    /// config lines and file structure so the GUI can tell which keys
    /// are overridden without discarding comments or blank lines.
    static func parse(text: String) -> [Block] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if text.hasSuffix("\n"), !lines.isEmpty {
            lines.removeLast()
        }

        var out: [Block] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                out.append(.blank)
                continue
            }
            if trimmed.hasPrefix("#") {
                out.append(.comment(text: line))
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let entry = line + "\n"
            if let last = out.last,
               case let .entry(previousKey, text) = last,
               previousKey == key {
                out[out.count - 1] = .entry(key: key, text: text + entry)
            } else {
                out.append(.entry(key: key, text: entry))
            }
        }
        return out
    }
}
