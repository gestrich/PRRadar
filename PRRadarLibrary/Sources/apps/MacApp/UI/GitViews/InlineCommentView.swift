import PRRadarModels
import SwiftUI

struct InlineCommentView: View {

    let comment: PRComment
    let prModel: PRModel
    var lineBackground: Color = .clear
    var gutterBackground: Color = Color.gray.opacity(0.1)
    var isHighlighted: Bool = false

    private var isSubmitting: Bool {
        prModel.submittingCommentIds.contains(comment.id)
    }

    private var isSubmitted: Bool {
        prModel.submittedCommentIds.contains(comment.id)
    }

    private var isSuppressed: Bool {
        comment.suppressionRole == .suppressed
    }

    private var isLimiting: Bool {
        comment.suppressionRole == .limiting
    }

    private var accentColor: Color {
        isSuppressed ? .gray : .blue
    }

    var body: some View {
        InlineCommentCard(accentColor: accentColor, lineBackground: lineBackground, gutterBackground: gutterBackground, highlightOpacity: isHighlighted ? 0.8 : 0) {
            VStack(alignment: .leading, spacing: 6) {
                if !isSuppressed, let position = prModel.violationPosition(for: comment.id) {
                    Text("\(position) of \(prModel.orderedViolations.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                }

                HStack(spacing: 8) {
                    SeverityBadge(score: comment.score)

                    if isSuppressed {
                        SuppressionBadge(label: "Suppressed")
                    } else if isLimiting {
                        let count = suppressedSiblingCount
                        if count > 0 {
                            SuppressionBadge(label: "\(count) more suppressed")
                        }
                    }

                    Spacer()

                    if !isSuppressed {
                        submitButton
                    }
                }

                RichContentView(comment.toGitHubMarkdown())
            }
        }
        .opacity(isSuppressed ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
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

    private var suppressedSiblingCount: Int {
        prModel.reviewComments.suppressedCount(
            forRule: comment.ruleName,
            filePath: comment.filePath
        )
    }
}
