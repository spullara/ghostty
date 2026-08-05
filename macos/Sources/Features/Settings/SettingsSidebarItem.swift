import Foundation

/// Selection wrapper for the Settings sidebar. Beyond the schema
/// categories we also expose a pinned "Config File" pane that shows
/// the raw config editor (Phase 4).
enum SettingsSidebarItem: Hashable, Identifiable {
    case category(SettingsCategory)
    case configFile

    var id: String {
        switch self {
        case .category(let c): return "cat:\(c.rawValue)"
        case .configFile: return "config-file"
        }
    }

    var title: String {
        switch self {
        case .category(let c): return c.title
        case .configFile: return "Configuration File"
        }
    }

    var systemImage: String {
        switch self {
        case .category(let c): return c.systemImage
        case .configFile: return "doc.text"
        }
    }
}
