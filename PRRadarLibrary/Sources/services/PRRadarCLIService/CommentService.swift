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
        let body = buildBody(comment: comment, commitSHA: commitSHA)

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

    /// Edit an existing review comment with updated body and metadata.
    public func editReviewComment(
        commentId: Int,
        comment: PRComment,
        commitSHA: String
    ) async throws {
        let body = buildBody(comment: comment, commitSHA: commitSHA)
        try await githubService.editReviewComment(commentId: commentId, body: body)
    }

    private func buildBody(comment: PRComment, commitSHA: String) -> String {
        var body = comment.toGitHubMarkdown()

        let metadata = comment.buildMetadata(prHeadSHA: commitSHA)
        body += "\n\n" + metadata.toHTMLComment()

        return body
    }

    private func buildBodyWithSuppression(comment: PRComment, commitSHA: String, suppressedCount: Int) -> String {
        var body = comment.toGitHubMarkdown()

        if suppressedCount > 0 {
            body += "\n\n" + CommentMetadata.suppressionIndicator(suppressedCount: suppressedCount, maxCommentsPerFile: comment.maxCommentsPerFile)
        }

        let metadata = comment.buildMetadata(prHeadSHA: commitSHA)
        body += "\n\n" + metadata.toHTMLComment()

        return body
    }

    /// Post a general comment on a PR (not inline).
    public func postComment(prNumber: Int, body: String) async throws {
        try await githubService.postIssueComment(number: prNumber, body: body)
    }

    /// Post all comments as inline review comments, with suppression-aware limiting indicators.
    ///
    /// Each tuple pairs the comment with its suppressed count (0 for normal comments,
    /// > 0 for limiting comments that carry the indicator text).
    /// Returns (successful, failed) counts.
    public func postViolations(
        comments: [(comment: PRComment, suppressedCount: Int)],
        prNumber: Int
    ) async throws -> (successful: Int, failed: Int) {
        let commitSHA = try await githubService.getPRHeadSHA(number: prNumber)

        var successful = 0
        var failed = 0

        for (comment, suppressedCount) in comments {
            do {
                let body = buildBodyWithSuppression(comment: comment, commitSHA: commitSHA, suppressedCount: suppressedCount)
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
                successful += 1
            } catch {
                print("  Failed to post comment on \(comment.filePath):\(comment.lineNumber ?? 0): \(error)")
                failed += 1
            }
        }

        return (successful, failed)
    }

    /// Edit existing comments that need updating, with suppression-aware limiting indicators.
    ///
    /// Each tuple pairs the comment (with suppressed count) and the GitHub comment ID to edit.
    /// Returns (successful, failed) counts.
    public func editViolations(
        comments: [(comment: PRComment, suppressedCount: Int, commentId: Int)],
        prNumber: Int
    ) async throws -> (successful: Int, failed: Int) {
        let commitSHA = try await githubService.getPRHeadSHA(number: prNumber)

        var successful = 0
        var failed = 0

        for (comment, suppressedCount, commentId) in comments {
            do {
                let body = buildBodyWithSuppression(comment: comment, commitSHA: commitSHA, suppressedCount: suppressedCount)
                try await githubService.editReviewComment(commentId: commentId, body: body)
                successful += 1
            } catch {
                print("  Failed to edit comment \(commentId) on \(comment.filePath):\(comment.lineNumber ?? 0): \(error)")
                failed += 1
            }
        }

        return (successful, failed)
    }
}
