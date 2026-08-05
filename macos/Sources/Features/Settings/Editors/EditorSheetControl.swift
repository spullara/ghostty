import SwiftUI

/// Trailing-column control for options whose editor is too rich to
/// squeeze into the row: shows a summary + "Edit…" button and
/// presents the dedicated editor as a sheet.
///
/// Individual editors provide their own bodies via ``content``; this
/// wrapper handles the sheet presentation and consistent Done/Cancel
/// affordances so every editor feels the same.
struct EditorSheetControl<Content: View>: View {
    let option: SettingsSchema.Option
    @ObservedObject var model: SettingsViewModel
    let summary: String
    @ViewBuilder let content: () -> Content

    @State private var isPresented: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(summary)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Button("Edit…") { isPresented = true }
        }
        .sheet(isPresented: $isPresented) {
            VStack(spacing: 0) {
                HStack {
                    Text(option.name)
                        .font(.system(.headline, design: .monospaced))
                    Spacer()
                    Button("Done") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
                Divider()
                content()
                    .frame(minWidth: 560, minHeight: 360)
            }
            .frame(minWidth: 640, minHeight: 480)
        }
    }
}
