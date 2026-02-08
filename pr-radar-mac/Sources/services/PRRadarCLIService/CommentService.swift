import CLISDK
import Foundation
import PRRadarModels

public struct CommentService: Sendable {
    private let githubService: GitHubService

    public init(githubService: GitHubService) {
        self.githubService = githubService
    }

    /// Get the HEAD commit SHA for a PR.
    public func getPRHeadSHA(prNumber: Int, repoPath: String) async throws -> String {
        let output = try await githubService.apiGet(
            endpoint: "repos/{owner}/{repo}/pulls/\(prNumber)",
            jq: ".head.sha",
            repoPath: repoPath
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// Post an inline review comment on a specific line of a PR.
    public func postReviewComment(
        prNumber: Int,
        violation: CommentableViolation,
        commitSHA: String,
        repoPath: String
    ) async throws {
        let body = violation.composeComment()

        if let lineNumber = violation.lineNumber {
            _ = try await githubService.apiPostWithInt(
                endpoint: "repos/{owner}/{repo}/pulls/\(prNumber)/comments",
                stringFields: [
                    "body": body,
                    "path": violation.filePath,
                    "side": "RIGHT",
                    "commit_id": commitSHA,
                ],
                intFields: ["line": lineNumber],
                repoPath: repoPath
            )
        } else {
            _ = try await githubService.apiPost(
                endpoint: "repos/{owner}/{repo}/issues/\(prNumber)/comments",
                fields: ["body": body],
                repoPath: repoPath
            )
        }
    }

    /// Post a general comment on a PR (not inline).
    public func postComment(prNumber: Int, body: String, repoPath: String) async throws {
        _ = try await githubService.apiPost(
            endpoint: "repos/{owner}/{repo}/issues/\(prNumber)/comments",
            fields: ["body": body],
            repoPath: repoPath
        )
    }

    /// Post all violations as inline review comments.
    ///
    /// Returns (successful, failed) counts.
    public func postViolations(
        violations: [CommentableViolation],
        prNumber: Int,
        repoPath: String
    ) async throws -> (successful: Int, failed: Int) {
        let commitSHA = try await getPRHeadSHA(prNumber: prNumber, repoPath: repoPath)

        var successful = 0
        var failed = 0

        for v in violations {
            do {
                try await postReviewComment(
                    prNumber: prNumber,
                    violation: v,
                    commitSHA: commitSHA,
                    repoPath: repoPath
                )
                successful += 1
            } catch {
                failed += 1
            }
        }

        return (successful, failed)
    }
}
