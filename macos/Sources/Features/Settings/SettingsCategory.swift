import Foundation

/// The curated groups shown in the Settings window sidebar. Every
/// option in the schema maps to exactly one category via
/// ``category(for:)``; unknown or uncategorized options fall through
/// to ``.advanced`` so new fields still appear in the UI without
/// requiring a code change here.
///
/// Ordering here is display order (top to bottom in the sidebar).
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case font
    case appearance
    case colors
    case cursor
    case window
    case tabsAndSplits
    case mouse
    case keyboard
    case clipboard
    case shell
    case notifications
    case quickTerminal
    case macos
    case advanced
    case otherPlatforms

    /// The special "Config File" pane (Phase 4) shows the raw config
    /// file editor; it does not contain schema options and is appended
    /// to the sidebar separately.
    static let configFile: SettingsCategory? = nil

    var id: String { rawValue }

    /// Human-readable label shown in the sidebar.
    var title: String {
        switch self {
        case .font: return "Font"
        case .appearance: return "Appearance & Theme"
        case .colors: return "Colors"
        case .cursor: return "Cursor"
        case .window: return "Window"
        case .tabsAndSplits: return "Tabs & Splits"
        case .mouse: return "Mouse"
        case .keyboard: return "Keyboard"
        case .clipboard: return "Clipboard"
        case .shell: return "Shell & Command"
        case .notifications: return "Notifications"
        case .quickTerminal: return "Quick Terminal"
        case .macos: return "macOS"
        case .advanced: return "Advanced"
        case .otherPlatforms: return "Other Platforms"
        }
    }

    /// SF Symbol shown in the sidebar row.
    var systemImage: String {
        switch self {
        case .font: return "textformat"
        case .appearance: return "paintpalette"
        case .colors: return "paintbrush"
        case .cursor: return "cursorarrow"
        case .window: return "macwindow"
        case .tabsAndSplits: return "rectangle.split.2x1"
        case .mouse: return "cursorarrow.motionlines"
        case .keyboard: return "keyboard"
        case .clipboard: return "doc.on.clipboard"
        case .shell: return "terminal"
        case .notifications: return "bell"
        case .quickTerminal: return "bolt"
        case .macos: return "apple.logo"
        case .advanced: return "wrench.and.screwdriver"
        case .otherPlatforms: return "square.grid.2x2"
        }
    }

    /// Return the category for a given option. Exact-name matches take
    /// precedence over prefix rules; everything unmatched lands in
    /// ``.advanced`` so new options are still reachable without a
    /// code change here (only their placement is generic).
    static func category(for name: String) -> SettingsCategory {
        if let exact = exactMap[name] { return exact }
        for (prefix, category) in prefixRules where name.hasPrefix(prefix) {
            return category
        }
        return .advanced
    }

    /// Curated exact-name overrides for options whose prefix would
    /// otherwise send them to the wrong bucket.
    private static let exactMap: [String: SettingsCategory] = [
        "theme": .appearance,
        "background": .colors,
        "foreground": .colors,
        "bold-color": .colors,
        "faint-opacity": .colors,
        "minimum-contrast": .colors,
        "background-opacity": .appearance,
        "background-blur": .appearance,
        "background-image": .appearance,
        "background-image-opacity": .appearance,
        "background-image-position": .appearance,
        "background-image-fit": .appearance,
        "background-image-repeat": .appearance,
        "unfocused-split-opacity": .tabsAndSplits,
        "unfocused-split-fill": .tabsAndSplits,
        "split-divider-color": .tabsAndSplits,
        "split-preserve-zoom": .tabsAndSplits,
        "split-inherit-working-directory": .tabsAndSplits,
        "tab-inherit-working-directory": .tabsAndSplits,
        "keybind": .keyboard,
        "key-remap": .keyboard,
        "input": .keyboard,
        "vt-kam-allowed": .keyboard,
        "command": .shell,
        "command-palette-entry": .keyboard,
        "initial-command": .shell,
        "working-directory": .shell,
        "wait-after-command": .shell,
        "abnormal-command-exit-runtime": .shell,
        "shell-integration": .shell,
        "shell-integration-features": .shell,
        "env": .shell,
        "term": .shell,
        "enquiry-response": .shell,
        "scrollback-limit": .advanced,
        "scrollback-compression": .advanced,
        "scrollbar": .appearance,
        "scroll-to-bottom": .advanced,
        "copy-on-select": .clipboard,
        "right-click-action": .mouse,
        "middle-click-action": .mouse,
        "click-repeat-interval": .mouse,
        "focus-follows-mouse": .mouse,
        "confirm-close-surface": .window,
        "maximize": .window,
        "fullscreen": .window,
        "resize-overlay": .window,
        "resize-overlay-position": .window,
        "resize-overlay-duration": .window,
        "quit-after-last-window-closed": .window,
        "quit-after-last-window-closed-delay": .window,
        "title": .window,
        "title-report": .window,
        "initial-window": .window,
        "class": .otherPlatforms,
        "x11-instance-name": .otherPlatforms,
        "app-notifications": .notifications,
        "desktop-notifications": .notifications,
        "progress-style": .notifications,
        "bell-features": .notifications,
        "bell-audio-path": .notifications,
        "bell-audio-volume": .notifications,
        "notify-on-command-finish": .notifications,
        "notify-on-command-finish-action": .notifications,
        "notify-on-command-finish-after": .notifications,
        "link": .mouse,
        "link-url": .mouse,
        "link-previews": .mouse,
        "auto-update": .advanced,
        "auto-update-channel": .advanced,
        "config-file": .advanced,
        "config-default-files": .advanced,
        "custom-shader": .appearance,
        "custom-shader-animation": .appearance,
        "grapheme-width-method": .advanced,
        "freetype-load-flags": .font,
        "alpha-blending": .appearance,
        "image-storage-limit": .advanced,
        "undo-timeout": .advanced,
        "osc-color-report-format": .advanced,
        "async-backend": .advanced,
        "language": .advanced,
        "palette": .colors,
        "palette-generate": .colors,
        "palette-harmonious": .colors,
        "selection-foreground": .colors,
        "selection-background": .colors,
        "selection-clear-on-typing": .mouse,
        "selection-clear-on-copy": .mouse,
        "selection-word-chars": .mouse,
        "search-foreground": .colors,
        "search-background": .colors,
        "search-selected-foreground": .colors,
        "search-selected-background": .colors,
        "clipboard-codepoint-map": .font,
    ]

    /// Prefix-based fallbacks, evaluated in order. First match wins.
    private static let prefixRules: [(String, SettingsCategory)] = [
        ("font-", .font),
        ("adjust-", .font),
        ("cursor-", .cursor),
        ("mouse-", .mouse),
        ("clipboard-", .clipboard),
        ("window-", .window),
        ("macos-", .macos),
        ("quick-terminal-", .quickTerminal),
        ("gtk-", .otherPlatforms),
        ("linux-", .otherPlatforms),
        ("adw-", .otherPlatforms),
    ]
}
