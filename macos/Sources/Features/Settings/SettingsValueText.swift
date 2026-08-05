import Foundation

/// Helpers for converting between the canonical config-file text
/// (produced by `ghostty_config_get_value_text`) and raw value
/// substrings that the UI can display/edit.
///
/// Canonical text looks like `"key = value\n"` (or several such
/// lines for repeatable options). These helpers only parse the
/// left-hand key and right-hand value; they never interpret the
/// value itself — that's the Zig config loader's job.
enum SettingsValueText {
    /// Extract the single trimmed value for `key` from canonical
    /// text. Returns an empty string if the key line is absent or
    /// the value is empty (which is how optional/unset values
    /// serialize). For repeatable types this returns only the first
    /// entry; specialized editors should parse the full text
    /// themselves via ``lines``.
    static func value(for key: String, in text: String) -> String {
        for line in lines(text) {
            if let value = parse(line: line, expectedKey: key) {
                return value
            }
        }
        return ""
    }

    /// Every non-empty, non-comment line in the given canonical text.
    static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    }

    /// Parse a single `key = value` line. Returns the trimmed value
    /// portion, or `nil` if the line does not name `expectedKey`.
    static func parse(line: String, expectedKey: String) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        guard key == expectedKey else { return nil }
        let after = line.index(after: eq)
        return String(line[after...]).trimmingCharacters(in: .whitespaces)
    }

    /// Build the canonical single-line text for `key = value`.
    /// Guaranteed to end with a newline so it can be dropped
    /// straight into the overlay file.
    static func format(key: String, value: String) -> String {
        "\(key) = \(value)\n"
    }

    /// Build canonical multi-line text for repeatable keys.
    static func format(key: String, values: [String]) -> String {
        if values.isEmpty { return "\(key) = \n" }
        return values.map { "\(key) = \($0)\n" }.joined()
    }
}
