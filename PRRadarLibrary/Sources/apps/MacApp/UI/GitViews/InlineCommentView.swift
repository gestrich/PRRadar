import PRRadarModels
import SwiftUI

struct InlineCommentView: View {

    let comment: PRComment
    let prModel: PRModel
    var lineBackground: Color = .clear
    var gutterBackground: Color = Color.gray.opacity(0.1)

    private var isSubmitting: Bool {
        prModel.submittingCommentIds.contains(comment.id)
    }

    private var isSubmitted: Bool {
        prModel.submittedCommentIds.contains(comment.id)
    }

    var body: some View {
        InlineCommentCard(accentColor: .blue, lineBackground: lineBackground, gutterBackground: gutterBackground) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SeverityBadge(score: comment.score)

                    Spacer()

                    submitButton
                }

                RichContentView(comment.toGitHubMarkdown())
            }
        }
    }

    @ViewBuilder
    private var submitButton: some View {
        if isSubmitted {
            Label("Submitted", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if isSubmitting {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Posting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button("Submit") {
                Task { await prModel.submitSingleComment(comment) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
