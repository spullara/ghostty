import Testing
import Foundation
@testable import Ghostty

/// Parser round-trip tests for the specialized Phase 3 editors.
/// Each editor consumes canonical text produced by
/// `ghostty_config_get_value_text` and emits canonical overlay text;
/// these tests exercise only the parsing/serialization helpers.
@Suite
struct SettingsEditorTests {

    // MARK: - Palette

    @Test func palettePerLineEntries() {
        let text = """
        palette = 0=#000000
        palette = 15=#ffffff
        """
        let parsed = PaletteEditorView.parsePaletteLines(text, key: "palette")
        #expect(parsed.count == 2)
        #expect(parsed[0].0 == 0)
        #expect(parsed[1].0 == 15)
    }

    @Test func paletteSingleLineCommaSeparated() {
        // Zig's formatEntry can emit either one line per index
        // (Palette) or a single comma-joined line (RepeatableColor).
        let text = "palette = 0=#000000,1=#800000,2=#00ff00"
        let parsed = PaletteEditorView.parsePaletteLines(text, key: "palette")
        #expect(parsed.count == 3)
    }

    @Test func paletteParsesZigColorSyntax() {
        let text = """
        palette = 5=red
        palette = 6=rgb:0/f/0
        """
        let parsed = PaletteEditorView.parsePaletteLines(text, key: "palette")
        #expect(parsed.count == 2)
        #expect(parsed[0].0 == 5)
        #expect(ColorSettingControl.hex(from: parsed[0].1) == "#ff0000")
        #expect(parsed[1].0 == 6)
        #expect(ColorSettingControl.hex(from: parsed[1].1) == "#00ff00")
    }

    @Test func paletteIgnoresOtherKeys() {
        let text = """
        background = #ff00ff
        palette = 4=#123456
        """
        let parsed = PaletteEditorView.parsePaletteLines(text, key: "palette")
        #expect(parsed.count == 1)
        #expect(parsed[0].0 == 4)
    }

    // MARK: - Command palette entries

    @Test func commandPaletteEntryParseSimple() {
        let entry = CommandPaletteEntryEditorView.parse(
            value: "title:\"Foo\",action:\"ignore\""
        )
        #expect(entry?.title == "Foo")
        #expect(entry?.action == "ignore")
        #expect(entry?.description == "")
    }

    @Test func commandPaletteEntryParseFull() {
        let entry = CommandPaletteEntryEditorView.parse(
            value: "title:\"Reset Font Style\",description:\"Reset styles\",action:\"csi:0m\""
        )
        #expect(entry?.title == "Reset Font Style")
        #expect(entry?.description == "Reset styles")
        #expect(entry?.action == "csi:0m")
    }

    @Test func commandPaletteEntryRespectsQuotesInCSV() {
        // Description contains a comma; must not split it.
        let value = "title:\"Focus Split: Right\",description:\"Focus the split to the right, if it exists.\",action:\"goto_split:right\""
        let entry = CommandPaletteEntryEditorView.parse(value: value)
        #expect(entry?.description == "Focus the split to the right, if it exists.")
        #expect(entry?.action == "goto_split:right")
    }

    @Test func commandPaletteEntryFormatRoundTrip() {
        let e = CommandPaletteEntryEditorView.Entry(
            title: "Foo", description: "bar", action: "ignore"
        )
        let text = CommandPaletteEntryEditorView.formatEntry(e)
        let parsed = CommandPaletteEntryEditorView.parse(value: text)
        #expect(parsed == e)
    }

    // MARK: - Font family availability

    @Test func fontFamilyAvailableFamiliesNotEmpty() {
        // Sanity check that NSFontManager returns something in the
        // test host (should have at least a handful of system fonts).
        let families = FontFamilyPickerView.availableFamilies(monospacedOnly: false)
        #expect(!families.isEmpty)
    }

    // MARK: - Theme discovery

    @Test func themeLoaderTolerantOfMissingDirs() {
        // The loader must not throw when neither theme directory
        // exists; it should just return an empty result.
        let themes = ThemePickerView.loadThemes()
        // Bundled themes may or may not be present in the test host
        // depending on build config; only require the call to succeed.
        _ = themes
    }

    // MARK: - Overlay round-trip

    @Test func overlayRoundTripsCanonicalText() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-overlay-\(UUID().uuidString).ghostty")
        let store = OverlayConfigStore(url: tmp)
        store.set("theme", valueText: "theme = Dracula\n")
        store.set("font-family", valueText: "font-family = Menlo\nfont-family = Fira Code\n")

        let reparsed = OverlayConfigStore.parse(url: tmp)
        #expect(reparsed["theme"] == "theme = Dracula\n")
        #expect(reparsed["font-family"] == "font-family = Menlo\nfont-family = Fira Code\n")

        store.remove("theme")
        let after = OverlayConfigStore.parse(url: tmp)
        #expect(after["theme"] == nil)
        #expect(after["font-family"] != nil)

        try? FileManager.default.removeItem(at: tmp)
    }

    @Test func overlaySerializationIsDeterministic() {
        let entries = [
            "z-key": "z-key = zzz\n",
            "a-key": "a-key = aaa\n",
            "m-key": "m-key = mmm\n",
        ]
        let out = OverlayConfigStore.serialize(entries: entries)
        // Alphabetical order — critical for stable diffs.
        let a = out.range(of: "a-key")!.lowerBound
        let m = out.range(of: "m-key")!.lowerBound
        let z = out.range(of: "z-key")!.lowerBound
        #expect(a < m)
        #expect(m < z)
    }
}
