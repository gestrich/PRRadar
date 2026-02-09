import PRRadarModels
import SwiftUI

struct InlinePostedCommentView: View {

    let comment: GitHubReviewComment
    var imageURLMap: [String: String]? = nil
    var imageBaseDir: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.green)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let author = comment.author {
                        Text(author.name.flatMap { $0.isEmpty ? nil : $0 } ?? author.login)
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

                RichContentView(comment.body, imageURLMap: imageURLMap, imageBaseDir: imageBaseDir)
            }
            .padding(12)
        }
        .background(.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}
