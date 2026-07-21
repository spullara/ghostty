import AppKit
import GhosttyKit
import SwiftUI

/// Editor for the primary Ghostty config file
/// (`~/.config/ghostty/config` or equivalent). The path is
/// discovered via `ghostty_config_open_path`, which also creates the
/// file if missing. Distinct from the Settings-window overlay: this
/// pane edits what the user's config file itself says.
struct ConfigFilePaneView: View {
    @ObservedObject var model: SettingsViewModel
    weak var ghostty: Ghostty.App?

    @State private var path: String = ""
    @State private var text: String = ""
    @State private var loadedText: String = ""
    @State private var loadError: String? = nil
    @State private var saveMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            banner
            Divider()
            ConfigTextEditor(text: $text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .onAppear { load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Configuration File").font(.title2).fontWeight(.semibold)
                if !path.isEmpty {
                    Text(path)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var banner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("This edits your main config file. Changes made in other Settings tabs live in a separate overlay (`settings-ui.ghostty`) that is loaded after this file, so overlay values win when both are set.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if let err = loadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if let msg = saveMessage {
                Text(msg).foregroundStyle(.secondary).font(.callout)
            } else if isDirty {
                Text("Modified").foregroundStyle(.secondary).font(.callout)
            }
            Spacer()
            Button("Reload") { load() }
                .disabled(path.isEmpty)
            Button("Open Externally") { openExternally() }
                .disabled(path.isEmpty)
            Button("Save") { save(reload: false) }
                .disabled(!isDirty || path.isEmpty)
            Button("Save & Reload") { save(reload: true) }
                .disabled(!isDirty || path.isEmpty)
                .keyboardShortcut("s", modifiers: [.command])
        }
        .padding()
    }

    private var isDirty: Bool { text != loadedText }

    // MARK: - Actions

    private func load() {
        saveMessage = nil
        loadError = nil
        let raw = ghostty_config_open_path()
        let resolved = Ghostty.AllocatedString(raw).string
        guard !resolved.isEmpty else {
            loadError = "Could not resolve config path."
            return
        }
        path = resolved
        do {
            let contents = try String(contentsOfFile: resolved, encoding: .utf8)
            text = contents
            loadedText = contents
        } catch {
            // File exists (openPath creates it) but may still be
            // unreadable in edge cases. Fall back to empty text.
            text = ""
            loadedText = ""
            loadError = "Failed to read config: \(error.localizedDescription)"
        }
    }

    private func save(reload: Bool) {
        saveMessage = nil
        loadError = nil
        guard !path.isEmpty else { return }
        do {
            let url = URL(fileURLWithPath: path)
            try text.write(to: url, atomically: true, encoding: .utf8)
            loadedText = text
            saveMessage = "Saved."
            if reload {
                ghostty?.reloadConfig()
                saveMessage = "Saved and reloaded."
            }
        } catch {
            loadError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func openExternally() {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

/// Monospaced NSTextView wrapper without smart substitutions. Plain
/// SwiftUI `TextEditor` is not usable here — it enables smart quotes
/// and auto-dashes that would corrupt config syntax.
struct ConfigTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        // Without an explicit small width the NSScrollView reports a
        // huge intrinsic size, which collapses the sidebar in the
        // parent NavigationSplitView. Keep it flexible via SwiftUI.
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let tv = scroll.documentView as! NSTextView
        tv.isEditable = true
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.allowsUndo = true
        tv.delegate = context.coordinator
        tv.string = text

        // Wrap long lines to the container width instead of scrolling
        // horizontally; this also stops the text view from requesting
        // unbounded width from its parent.
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ConfigTextEditor
        init(_ parent: ConfigTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
