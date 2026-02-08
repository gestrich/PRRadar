import Foundation
import PRRadarModels

public struct CommentService: Sendable {
    private let githubService: GitHubService

    public init(githubService: GitHubService) {
        self.githubService = githubService
    }

    /// Post an inline review comment on a specific line of a PR.
    public func postReviewComment(
        prNumber: Int,
        violation: CommentableViolation,
        commitSHA: String
    ) async throws {
        let body = violation.composeComment()

        if let lineNumber = violation.lineNumber {
            try await githubService.postReviewComment(
                number: prNumber,
                commitId: commitSHA,
                path: violation.filePath,
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

    /// Post all violations as inline review comments.
    ///
    /// Returns (successful, failed) counts.
    public func postViolations(
        violations: [CommentableViolation],
        prNumber: Int
    ) async throws -> (successful: Int, failed: Int) {
        let commitSHA = try await githubService.getPRHeadSHA(number: prNumber)

        var successful = 0
        var failed = 0

        for v in violations {
            do {
                try await postReviewComment(
                    prNumber: prNumber,
                    violation: v,
                    commitSHA: commitSHA
                )
                successful += 1
            } catch {
                failed += 1
            }
        }

        return (successful, failed)
    }
}
