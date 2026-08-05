import AppKit
import SwiftUI

/// Window controller for the Settings window. Programmatically built
/// (no separate `.xib`) so it can be added without touching the
/// Xcode project; the SwiftUI view tree lives in ``SettingsView``.
///
/// One-per-app: use the shared instance via
/// ``AppDelegate.showSettings(_:)``. Bringing the window forward
/// twice just re-focuses the existing window.
final class SettingsController: NSWindowController, NSWindowDelegate {
    /// Weak back-reference so we can pull the current
    /// `Ghostty.Config` and inject the app delegate into the SwiftUI
    /// environment.
    private weak var appDelegate: AppDelegate?

    convenience init(appDelegate: AppDelegate) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        self.init(window: window)
        self.appDelegate = appDelegate
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsView().environmentObject(appDelegate)
        )
    }

    /// Bring the Settings window to the front, creating it on first
    /// use. Also seeds the view model with the current config so the
    /// UI shows correct values immediately (before the next reload).
    func show() {
        guard let appDelegate else { return }
        if let schema = SettingsSchema.shared {
            let vm = appDelegate.settingsViewModel(schema: schema)
            vm.refreshEffectiveValues(config: appDelegate.ghostty.config)
            vm.updateDiagnostics(from: appDelegate.ghostty.config)
            vm.acknowledgeRestartHint()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - First Responder

    @IBAction func close(_ sender: Any) {
        window?.performClose(sender)
    }
}
