import AppKit
import PRRadarModels
import SwiftUI

/// A simple view for displaying raw git diff text
public struct SimpleDiffView: View {
    let diff: GitDiff
    let title: String
    @Environment(\.dismiss) private var dismiss

    public init(diff: GitDiff, title: String) {
        self.diff = diff
        self.title = title
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.title2)
                    .bold()

                Spacer()

                Button(action: copyDiff) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Diff content
            ScrollView {
                Text(diff.rawContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func copyDiff() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diff.rawContent, forType: .string)
    }
}
