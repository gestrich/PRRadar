import PRRadarModels
import SwiftUI

struct SummaryPhaseView: View {

    let metadata: PRMetadata
    let postedComments: [GitHubComment]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                prInfoSection
                if !postedComments.isEmpty {
                    commentsSection
                }
            }
            .padding()
        }
    }

    // MARK: - PR Info Section

    @ViewBuilder
    private var prInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(metadata.number)")
                    .font(.title.bold())
                    .foregroundStyle(.secondary)

                Text(metadata.title)
                    .font(.title.bold())
            }

            HStack(spacing: 16) {
                if !metadata.author.login.isEmpty {
                    Label(
                        metadata.author.name.isEmpty ? metadata.author.login : metadata.author.name,
                        systemImage: "person"
                    )
                }

                if !metadata.headRefName.isEmpty {
                    Label(metadata.headRefName, systemImage: "arrow.triangle.branch")
                        .font(.system(.body, design: .monospaced))
                }

                if !metadata.state.isEmpty {
                    Label(metadata.state.capitalized, systemImage: "circle.fill")
                        .foregroundStyle(stateColor)
                }

                if !metadata.createdAt.isEmpty {
                    Label(formattedDate, systemImage: "calendar")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let body = metadata.body, !body.isEmpty {
                Divider()

                RichContentView(body)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private var stateColor: Color {
        switch metadata.state.uppercased() {
        case "OPEN": .green
        case "CLOSED": .red
        case "MERGED": .purple
        case "DRAFT": .orange
        default: .secondary
        }
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: metadata.createdAt) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return metadata.createdAt
    }

    // MARK: - Comments Section

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PR Comments (\(postedComments.count))")
                .font(.headline)

            ForEach(postedComments, id: \.id) { comment in
                commentRow(comment)
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: GitHubComment) -> some View {
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

                RichContentView(comment.body)
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
