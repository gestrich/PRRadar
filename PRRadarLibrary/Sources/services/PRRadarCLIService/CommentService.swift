import Foundation
import PRRadarModels

public struct CommentService: Sendable {
    private let githubService: GitHubService

    public init(githubService: GitHubService) {
        self.githubService = githubService
    }

    /// Post a review comment for a PRComment on a specific line of a PR.
    public func postReviewComment(
        prNumber: Int,
        comment: PRComment,
        commitSHA: String
    ) async throws {
        let body = comment.toGitHubMarkdown()

        if let lineNumber = comment.lineNumber {
            try await githubService.postReviewComment(
                number: prNumber,
                commitId: commitSHA,
                path: comment.filePath,
                line: lineNumber,
                body: body
            )
        } else {
            try await githubService.postIssueComment(
                number: prNumber,
                body: body
            )
        }
    }

    /// Post a general comment on a PR (not inline).
    public func postComment(prNumber: Int, body: String) async throws {
        try await githubService.postIssueComment(number: prNumber, body: body)
    }

    /// Post all comments as inline review comments.
    ///
    /// Returns (successful, failed) counts.
    public func postViolations(
        comments: [PRComment],
        prNumber: Int
    ) async throws -> (successful: Int, failed: Int) {
        let commitSHA = try await githubService.getPRHeadSHA(number: prNumber)

        var successful = 0
        var failed = 0

        for comment in comments {
            do {
                try await postReviewComment(
                    prNumber: prNumber,
                    comment: comment,
                    commitSHA: commitSHA
                )
                successful += 1
            } catch {
                print("  Failed to post comment on \(comment.filePath):\(comment.lineNumber ?? 0): \(error)")
                failed += 1
            }
        }

        return (successful, failed)
    }
}
