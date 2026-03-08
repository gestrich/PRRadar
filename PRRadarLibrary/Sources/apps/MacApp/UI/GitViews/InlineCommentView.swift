import PRRadarModels
import SwiftUI

struct InlineCommentView: View {

    let comment: PRComment
    let prModel: PRModel
    var lineBackground: Color = .clear
    var gutterBackground: Color = Color.gray.opacity(0.1)
    var isHighlighted: Bool = false

    @State private var highlightOpacity: Double = 0

    private var isSubmitting: Bool {
        prModel.submittingCommentIds.contains(comment.id)
    }

    private var isSubmitted: Bool {
        prModel.submittedCommentIds.contains(comment.id)
    }

    var body: some View {
        InlineCommentCard(accentColor: .blue, lineBackground: lineBackground, gutterBackground: gutterBackground, highlightOpacity: highlightOpacity) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SeverityBadge(score: comment.score)

                    Spacer()

                    submitButton
                }

                RichContentView(comment.toGitHubMarkdown())
            }
        }
        .onAppear { triggerHighlightIfNeeded() }
        .onChange(of: isHighlighted) { _, highlighted in
            if highlighted { triggerHighlightIfNeeded() }
        }
    }

    private func triggerHighlightIfNeeded() {
        guard isHighlighted else { return }
        withAnimation(.easeIn(duration: 0.2)) {
            highlightOpacity = 0.8
        }
        withAnimation(.easeOut(duration: 1.0).delay(0.8)) {
            highlightOpacity = 0
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
