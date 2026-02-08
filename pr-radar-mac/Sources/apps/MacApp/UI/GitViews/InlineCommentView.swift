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

                    Text(comment.ruleName)
                        .font(.subheadline.bold())

                    Spacer()

                    submitButton
                }

                Text(comment.comment)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let link = comment.documentationLink, let url = URL(string: link) {
                    HStack(spacing: 4) {
                        Image(systemName: "book")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Link("Documentation", destination: url)
                            .font(.caption)
                    }
                }
            }
            .padding(10)
        }
        .background(Color.blue.opacity(0.06))
        .overlay(
            Rectangle()
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
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
