import Foundation
import OSLog

/// A decoded representation of `settings-schema.json`, emitted by the
/// Zig `settingsgen` executable at build time and copied into the app
/// bundle under `Resources/ghostty/settings-schema.json`.
///
/// This is the single source of truth for what the Settings UI knows
/// about: field names, kinds, defaults, docs, and the catalog of
/// keybind actions. The schema is loaded once via ``load()`` and cached
/// on the type.
struct SettingsSchema: Decodable {
    /// Schema format version, bumped whenever the JSON shape changes
    /// incompatibly (see `src/build/settingsgen/main.zig`).
    let version: Int

    /// Every top-level config field, in the order emitted by
    /// `settingsgen` (which matches Config.zig field order).
    let options: [Option]

    /// Every keybind action known to Ghostty, used by the keybind
    /// editor to populate its action picker.
    let keybindActions: [KeybindAction]

    enum CodingKeys: String, CodingKey {
        case version
        case options
        case keybindActions = "keybind_actions"
    }

    /// A single configurable option.
    struct Option: Decodable, Identifiable, Hashable {
        var id: String { name }

        /// The dashed config key name (e.g. `font-family`).
        let name: String

        /// The current default value serialized in canonical
        /// config-file text form ("key = value\n", possibly multi-line
        /// for repeatable types).
        let `default`: String

        /// The doc comment for the field, verbatim from
        /// `help_strings`. May be empty.
        let docs: String

        /// True if the underlying Zig type is optional. The
        /// generator omits this key when the field is required, so
        /// it decodes as `false` in that case.
        let optional: Bool

        /// The classification used by the UI to pick a control.
        let kind: Kind

        /// For `kind == .enum`, the set of accepted variant names.
        let values: [String]?

        /// For `kind == .packedBools`, the set of field names inside
        /// the packed struct (each rendered as a Toggle).
        let fields: [String]?

        /// For `kind == .int`, the bit width of the underlying integer.
        let bits: Int?

        /// For `kind == .int`, whether the integer is signed.
        let signed: Bool?

        /// For `kind == .color`, additional non-color tokens the value
        /// may take (e.g. `cell-foreground`).
        let specialValues: [String]?

        enum CodingKeys: String, CodingKey {
            case name, `default`, docs, optional, kind, values, fields, bits, signed
            case specialValues = "special_values"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try c.decode(String.self, forKey: .name)
            self.default = try c.decode(String.self, forKey: .default)
            self.docs = try c.decodeIfPresent(String.self, forKey: .docs) ?? ""
            self.optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? false
            self.kind = try c.decode(Kind.self, forKey: .kind)
            self.values = try c.decodeIfPresent([String].self, forKey: .values)
            self.fields = try c.decodeIfPresent([String].self, forKey: .fields)
            self.bits = try c.decodeIfPresent(Int.self, forKey: .bits)
            self.signed = try c.decodeIfPresent(Bool.self, forKey: .signed)
            self.specialValues = try c.decodeIfPresent([String].self, forKey: .specialValues)
        }

        /// A human-readable rendering of ``name`` suitable for row
        /// labels. Derived by title-casing the dashed key and applying
        /// a small acronym override table so `macos-titlebar-style`
        /// becomes "macOS Titlebar Style" rather than "Macos Titlebar
        /// Style". The raw ``name`` is still the authoritative key and
        /// should remain accessible on hover.
        var displayName: String {
            SettingsSchema.humanize(name)
        }
    }

    /// Convert a dashed config key such as `macos-titlebar-style` into
    /// a human-readable title such as "macOS Titlebar Style". Known
    /// acronyms and product names keep their canonical casing.
    static func humanize(_ key: String) -> String {
        key.split(separator: "-").map { part -> String in
            let lower = part.lowercased()
            if let override = acronymOverrides[lower] { return override }
            guard let first = part.first else { return "" }
            return first.uppercased() + part.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// Lowercased dashed-segment overrides applied by ``humanize``.
    private static let acronymOverrides: [String: String] = [
        "macos": "macOS",
        "ios": "iOS",
        "gtk": "GTK",
        "kde": "KDE",
        "x11": "X11",
        "osc": "OSC",
        "vt": "VT",
        "csi": "CSI",
        "sgr": "SGR",
        "utf8": "UTF-8",
        "url": "URL",
        "ui": "UI",
        "cli": "CLI",
        "tls": "TLS",
        "ssh": "SSH",
        "cwd": "CWD",
        "id": "ID",
        "ipc": "IPC",
        "api": "API",
        "http": "HTTP",
        "png": "PNG",
        "rgb": "RGB",
        "rgba": "RGBA",
        "dpi": "DPI",
        "srgb": "sRGB",
    ]

    /// The classification used to pick a UI control for a given option.
    /// Must stay in sync with the `kind` strings emitted by
    /// `src/build/settingsgen/main.zig`.
    enum Kind: String, Decodable {
        case bool
        case int
        case float
        case string
        case `enum`
        case color
        case colorList = "color-list"
        case packedBools = "packed-bools"
        case duration
        case path
        case repeatablePath = "repeatable-path"
        case repeatableString = "repeatable-string"
        case stringMap = "string-map"
        case keybinds
        case palette
        case commandPaletteEntry = "command-palette-entry"
        case codepointMap = "codepoint-map"
        case theme
        case fontStyle = "font-style"
        case command
        case custom
    }

    /// A keybind action descriptor, used by the keybind editor.
    struct KeybindAction: Decodable, Identifiable, Hashable {
        var id: String { name }

        let name: String
        let docs: String
        let argument: Argument

        struct Argument: Decodable, Hashable {
            let kind: ArgumentKind
            let values: [String]?
        }

        enum ArgumentKind: String, Decodable {
            case none
            case int
            case string
            case `enum`
            case custom
        }
    }

    // MARK: - Loading

    /// Log for schema loading failures.
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "SettingsSchema"
    )

    /// Cached load; `nil` if the schema is missing or fails to decode.
    static let shared: SettingsSchema? = load()

    private static func load() -> SettingsSchema? {
        guard let url = schemaURL() else {
            logger.error("settings-schema.json not found in bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SettingsSchema.self, from: data)
        } catch {
            logger.error("failed to decode settings-schema.json: \(error, privacy: .public)")
            return nil
        }
    }

    /// Locate the schema in whichever bundle contains it. Checks
    /// `Bundle.main` first (production case), then walks
    /// `Bundle.allBundles`, and finally probes a few known-relative
    /// paths so that xctest bundles hosted inside `Ghostty.app` can
    /// still find the resource in `Contents/Resources/ghostty/`.
    private static func schemaURL() -> URL? {
        for bundle in [Bundle.main] + Bundle.allBundles {
            if let url = bundle.url(
                forResource: "settings-schema",
                withExtension: "json",
                subdirectory: "ghostty"
            ) {
                return url
            }
        }
        let fm = FileManager.default
        var url = Bundle(for: BundleFinder.self).bundleURL
        for _ in 0..<6 {
            let candidate = url
                .appendingPathComponent("Contents/Resources/ghostty/settings-schema.json")
            if fm.fileExists(atPath: candidate.path) { return candidate }
            url = url.deletingLastPathComponent()
            if url.pathComponents.count <= 1 { break }
        }
        return nil
    }

    /// Marker class used solely as a `Bundle(for:)` anchor.
    private final class BundleFinder {}
}
