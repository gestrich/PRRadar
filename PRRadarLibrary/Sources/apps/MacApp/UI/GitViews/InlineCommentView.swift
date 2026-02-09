import PRRadarModels
import SwiftUI

struct InlineCommentView: View {

    let comment: PRComment
    let prModel: PRModel

    private var isSubmitting: Bool {
        prModel.submittingCommentIds.contains(comment.id)
    }

    private var isSubmitted: Bool {
        prModel.submittedCommentIds.contains(comment.id)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SeverityBadge(score: comment.score)

                    Spacer()

                    submitButton
                }

                RichContentView(comment.toGitHubMarkdown())
            }
            .padding(12)
        }
        .background(.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
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
