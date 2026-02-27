import PRRadarModels
import SwiftUI

struct InlinePostedCommentView: View {

    let comment: GitHubReviewComment
    var isRedetected: Bool = false
    var imageURLMap: [String: String]? = nil
    var imageBaseDir: String? = nil
    var lineBackground: Color = .clear
    var gutterBackground: Color = Color.gray.opacity(0.1)

    var body: some View {
        InlineCommentCard(accentColor: .green, lineBackground: lineBackground, gutterBackground: gutterBackground) {
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

                    if isRedetected {
                        Label("Still detected in latest analysis", systemImage: "arrow.trianglehead.2.counterclockwise")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    if let urlString = comment.url, let url = URL(string: urlString) {
                        Link("View on GitHub", destination: url)
                            .font(.caption)
                    }
                }

                RichContentView(comment.body, imageURLMap: imageURLMap, imageBaseDir: imageBaseDir)
            }
        }
    }
}
