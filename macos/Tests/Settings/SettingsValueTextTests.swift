import Testing
@testable import Ghostty

@Suite
struct SettingsValueTextTests {
    @Test func extractsSingleValue() {
        let text = "font-size = 14\n"
        #expect(SettingsValueText.value(for: "font-size", in: text) == "14")
    }

    @Test func missingKeyReturnsEmpty() {
        let text = "theme = GruvboxDark\n"
        #expect(SettingsValueText.value(for: "font-size", in: text).isEmpty)
    }

    @Test func commentsAndBlankLinesIgnored() {
        let text = """
            # a comment
            \nfont-size = 14
            """
        #expect(SettingsValueText.value(for: "font-size", in: text) == "14")
    }

    @Test func formatSingleValueHasTrailingNewline() {
        let text = SettingsValueText.format(key: "font-size", value: "14")
        #expect(text == "font-size = 14\n")
    }

    @Test func formatMultipleValuesRepeatsKey() {
        let text = SettingsValueText.format(
            key: "keybind",
            values: ["ctrl+a=copy_to_clipboard", "ctrl+v=paste_from_clipboard"]
        )
        #expect(text ==
            "keybind = ctrl+a=copy_to_clipboard\nkeybind = ctrl+v=paste_from_clipboard\n")
    }

    @Test func parseLineMatchesExpectedKeyOnly() {
        #expect(SettingsValueText.parse(line: "font-size = 14", expectedKey: "font-size") == "14")
        #expect(SettingsValueText.parse(line: "theme = X", expectedKey: "font-size") == nil)
    }
}
