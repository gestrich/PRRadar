import PRRadarModels
import SwiftUI

struct InlinePostedCommentView: View {

    let comment: GitHubReviewComment

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.green)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let author = comment.author {
                        Text(author.login)
                            .font(.subheadline.bold())
                    }

                    if let createdAt = comment.createdAt {
                        Text(createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let urlString = comment.url, let url = URL(string: urlString) {
                        Link("View on GitHub", destination: url)
                            .font(.caption)
                    }
                }

                Text(comment.body)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
        }
        .background(Color.green.opacity(0.06))
        .overlay(
            Rectangle()
                .stroke(Color.green.opacity(0.15), lineWidth: 1)
        )
    }
}
