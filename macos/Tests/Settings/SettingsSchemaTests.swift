import Testing
import Foundation
@testable import Ghostty

@Suite
struct SettingsSchemaTests {
    /// The bundled schema must load and cover a non-trivial number
    /// of options; if this drops to zero the JSON resource wasn't
    /// copied into the app bundle.
    @Test func schemaLoadsFromBundle() throws {
        let schema = try #require(SettingsSchema.shared)
        #expect(schema.options.count > 100)
        #expect(!schema.keybindActions.isEmpty)
    }

    /// Every schema option gets categorised. A missing category
    /// would silently drop the option from the UI.
    @Test func everyOptionHasCategory() throws {
        let schema = try #require(SettingsSchema.shared)
        for option in schema.options {
            let category = SettingsCategory.category(for: option.name)
            // The category enum's `allCases` must contain the
            // resolved category; this fires if `category(for:)`
            // ever returns a value that isn't part of the sidebar.
            #expect(SettingsCategory.allCases.contains(category))
        }
    }

    /// A handful of well-known options must land in the expected
    /// category so we don't silently regress the curated map.
    @Test func curatedCategoryMappings() {
        #expect(SettingsCategory.category(for: "font-size") == .font)
        #expect(SettingsCategory.category(for: "background") == .colors)
        #expect(SettingsCategory.category(for: "keybind") == .keyboard)
        #expect(SettingsCategory.category(for: "window-decoration") == .window)
    }
}
