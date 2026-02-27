import SwiftUI

struct InlineCommentComposeView: View {

    let filePath: String
    let lineNumber: Int
    let prModel: PRModel
    var lineBackground: Color = .clear
    var gutterBackground: Color = Color.gray.opacity(0.1)
    var onCancel: () -> Void

    @State private var commentText = ""
    @State private var isPosting = false

    var body: some View {
        InlineCommentCard(accentColor: .purple, lineBackground: lineBackground, gutterBackground: gutterBackground) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New comment on line \(lineNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $commentText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 120)

                HStack(spacing: 8) {
                    Spacer()

                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        isPosting = true
                        Task {
                            await prModel.postManualComment(
                                filePath: filePath,
                                lineNumber: lineNumber,
                                body: commentText
                            )
                            isPosting = false
                            onCancel()
                        }
                    } label: {
                        if isPosting {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Posting...")
                            }
                        } else {
                            Text("Post Comment")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
            }
        }
    }
}
