import PRRadarModels
import SwiftUI

struct InlineCommentView: View {

    let evaluation: RuleEvaluationResult

    @Environment(ReviewModel.self) private var reviewModel

    private var isSubmitting: Bool {
        reviewModel.submittingCommentIds.contains(evaluation.taskId)
    }

    private var isSubmitted: Bool {
        reviewModel.submittedCommentIds.contains(evaluation.taskId)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SeverityBadge(score: evaluation.evaluation.score)

                    Text(evaluation.ruleName)
                        .font(.subheadline.bold())

                    Spacer()

                    submitButton
                }

                Text(evaluation.evaluation.comment)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
                Task { await reviewModel.submitSingleComment(evaluation) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
