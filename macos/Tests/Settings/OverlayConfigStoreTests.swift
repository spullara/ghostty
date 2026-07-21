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

    /// Deterministic serialisation: entries are emitted in
    /// alphabetical key order so overlay-file diffs stay stable.
    @Test func serializeSortsKeys() {
        let text = OverlayConfigStore.serialize(entries: [
            "theme": "theme = GruvboxDark\n",
            "font-size": "font-size = 14\n",
        ])
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines == ["font-size = 14", "theme = GruvboxDark"])
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
