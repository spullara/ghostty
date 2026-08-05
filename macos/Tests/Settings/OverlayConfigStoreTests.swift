import Testing
import Foundation
@testable import Ghostty

@Suite
struct OverlayConfigStoreTests {
    /// A round-trip write/read must preserve entries verbatim so
    /// that the config loader parses exactly what the UI wrote.
    @Test func writeReadRoundTrip() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = OverlayConfigStore(url: url)
        store.set("font-size", valueText: "font-size = 14\n")
        store.set("theme", valueText: "theme = GruvboxDark\n")

        // Re-open from disk to verify persistence.
        let reloaded = OverlayConfigStore(url: url)
        #expect(reloaded.entries["font-size"] == "font-size = 14\n")
        #expect(reloaded.entries["theme"] == "theme = GruvboxDark\n")
    }

    /// Removing an entry drops it from disk on the next read.
    @Test func removePersistsDeletion() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = OverlayConfigStore(url: url)
        store.set("font-size", valueText: "font-size = 14\n")
        store.remove("font-size")

        let reloaded = OverlayConfigStore(url: url)
        #expect(reloaded.entries["font-size"] == nil)
    }

    /// Repeatable-key values (multi-line canonical text) survive a
    /// round-trip with all lines intact.
    @Test func repeatableKeysRoundTrip() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = OverlayConfigStore(url: url)
        let text = "keybind = ctrl+a=copy_to_clipboard\nkeybind = ctrl+v=paste_from_clipboard\n"
        store.set("keybind", valueText: text)

        let reloaded = OverlayConfigStore(url: url)
        #expect(reloaded.entries["keybind"] == text)
    }

    /// `loadText()` returns the empty string when the overlay file
    /// doesn't exist, so `ghostty_config_load_string` can be safely
    /// skipped in `Ghostty.Config.loadConfig`.
    @Test func loadTextMissingFileIsEmpty() {
        let url = Self.tempURL()
        try? FileManager.default.removeItem(at: url)
        let store = OverlayConfigStore(url: url)
        #expect(store.loadText().isEmpty)
    }

    /// Serialisation preserves file order, comments, and blank lines.
    @Test func parseSerializePreservesStructure() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let original = """
        # Custom note

        theme = Dracula
        # Keybindings
        keybind = ctrl+a=copy_to_clipboard
        keybind = ctrl+v=paste_from_clipboard
        font-size = 14
        """
        try original.write(to: url, atomically: true, encoding: .utf8)

        let parsed = OverlayConfigStore.parseFile(url: url)
        #expect(OverlayConfigStore.serialize(
            entries: parsed.blocks,
            trailingNewline: parsed.hasTrailingNewline
        ) == original)

        let reloaded = OverlayConfigStore(url: url)
        // Entry values are canonical config text and always terminate
        // with a newline, regardless of whether the source file did.
        let keybinds = """
        keybind = ctrl+a=copy_to_clipboard
        keybind = ctrl+v=paste_from_clipboard

        """
        #expect(reloaded.entries["keybind"] == keybinds)
    }

    /// New GUI-written entries are appended instead of reordering the
    /// whole file alphabetically.
    @Test func setAppendsNewEntryWithoutSorting() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let original = """
        z-key = zzz
        # Keep this comment with the existing entry.

        """
        try original.write(to: url, atomically: true, encoding: .utf8)

        let store = OverlayConfigStore(url: url)
        store.set("a-key", valueText: "a-key = aaa\n")

        let saved = try String(contentsOf: url, encoding: .utf8)
        let z = saved.range(of: "z-key = zzz")!.lowerBound
        let comment = saved.range(of: "# Keep this comment")!.lowerBound
        let a = saved.range(of: "a-key = aaa")!.lowerBound
        #expect(z < comment)
        #expect(comment < a)
    }

    private static func tempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-overlay-tests", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent(
            "\(UUID().uuidString).ghostty",
            isDirectory: false
        )
    }
}
