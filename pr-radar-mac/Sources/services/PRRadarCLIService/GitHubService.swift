import Foundation
@preconcurrency import OctoKit
import PRRadarMacSDK
import PRRadarModels

public struct GitHubService: Sendable {
    private let octokitClient: OctokitClient
    private let owner: String
    private let repo: String

    public init(octokitClient: OctokitClient, owner: String, repo: String) {
        self.octokitClient = octokitClient
        self.owner = owner
        self.repo = repo
    }

    // MARK: - Pull Request Operations

    public func getPRDiff(number: Int) async throws -> String {
        try await octokitClient.getPullRequestDiff(owner: owner, repository: repo, number: number)
    }

    public func getPullRequest(number: Int) async throws -> GitHubPullRequest {
        let pr = try await octokitClient.pullRequest(owner: owner, repository: repo, number: number)
        let files = try await octokitClient.listPullRequestFiles(owner: owner, repository: repo, number: number)
        return pr.toGitHubPullRequest(files: files)
    }

    public func getPullRequestComments(number: Int) async throws -> GitHubPullRequestComments {
        let issueComments = try await octokitClient.issueComments(
            owner: owner, repository: repo, number: number
        )
        let comments = issueComments.map { comment in
            GitHubComment(
                id: String(comment.id),
                body: comment.body,
                author: comment.user.toGitHubAuthor(),
                createdAt: formatISO8601(comment.createdAt),
                url: comment.htmlURL.absoluteString
            )
        }

        let reviewList = try await octokitClient.listReviews(
            owner: owner, repository: repo, number: number
        )
        let reviews = reviewList.map { review in
            GitHubReview(
                id: String(review.id),
                body: review.body,
                state: review.state.rawValue,
                author: review.user.toGitHubAuthor(),
                submittedAt: review.submittedAt.map { formatISO8601($0) }
            )
        }

        return GitHubPullRequestComments(comments: comments, reviews: reviews)
    }

    public func listPullRequests(
        limit: Int,
        state: String
    ) async throws -> [GitHubPullRequest] {
        let filterMerged = state.lowercased() == "merged"

        let openness: Openness
        switch state.lowercased() {
        case "closed", "merged": openness = .closed
        case "all": openness = .all
        default: openness = .open
        }

        let prs = try await octokitClient.listPullRequests(
            owner: owner,
            repository: repo,
            state: openness,
            perPage: String(limit)
        )

        let mapped = prs.map { $0.toGitHubPullRequest() }

        if filterMerged {
            return mapped.filter { $0.mergedAt != nil }
        }
        return mapped
    }

    public func getRepository() async throws -> GitHubRepository {
        let repo = try await octokitClient.repository(owner: owner, name: self.repo)
        return repo.toGitHubRepository()
    }

    // MARK: - Comment Operations

    public func getPRHeadSHA(number: Int) async throws -> String {
        try await octokitClient.getPullRequestHeadSHA(owner: owner, repository: repo, number: number)
    }

    public func postIssueComment(number: Int, body: String) async throws {
        _ = try await octokitClient.postIssueComment(owner: owner, repository: repo, number: number, body: body)
    }

    public func postReviewComment(
        number: Int,
        commitId: String,
        path: String,
        line: Int,
        body: String
    ) async throws {
        _ = try await octokitClient.postReviewComment(
            owner: owner,
            repository: repo,
            number: number,
            commitId: commitId,
            path: path,
            line: line,
            body: body
        )
    }

    // MARK: - Factory

    /// Parse owner and repo name from a git remote URL.
    ///
    /// Supports formats:
    /// - `https://github.com/owner/repo.git`
    /// - `git@github.com:owner/repo.git`
    /// - URLs with or without `.git` suffix
    public static func parseOwnerRepo(from remoteURL: String) -> (owner: String, repo: String)? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // SSH format: git@github.com:owner/repo.git
        if trimmed.contains("@") && trimmed.contains(":") {
            let afterColon = trimmed.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            let parts = afterColon
                .replacingOccurrences(of: ".git", with: "")
                .split(separator: "/")
            guard parts.count >= 2 else { return nil }
            return (String(parts[parts.count - 2]), String(parts[parts.count - 1]))
        }

        // HTTPS format: https://github.com/owner/repo.git
        if let url = URL(string: trimmed) {
            let parts = url.pathComponents
                .filter { $0 != "/" }
                .map { $0.replacingOccurrences(of: ".git", with: "") }
            guard parts.count >= 2 else { return nil }
            return (parts[parts.count - 2], parts[parts.count - 1])
        }

        return nil
    }
}
