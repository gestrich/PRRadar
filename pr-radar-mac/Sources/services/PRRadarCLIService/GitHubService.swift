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

        let reviewCommentList = try await octokitClient.listPullRequestReviewComments(
            owner: owner, repository: repo, number: number
        )
        let reviewComments = reviewCommentList.map { rc in
            GitHubReviewComment(
                id: String(rc.id),
                body: rc.body,
                path: rc.path,
                line: rc.line,
                startLine: rc.startLine,
                author: rc.userLogin.map { GitHubAuthor(login: $0, id: rc.userId.map(String.init)) },
                createdAt: rc.createdAt,
                url: rc.htmlUrl,
                inReplyToId: rc.inReplyToId.map(String.init)
            )
        }

        return GitHubPullRequestComments(comments: comments, reviews: reviews, reviewComments: reviewComments)
    }

    public func listPullRequests(
        limit: Int,
        state: PRState?,
        since: Date? = nil
    ) async throws -> [GitHubPullRequest] {
        let openness: Openness
        if let state {
            switch state.apiStateValue {
            case "closed": openness = .closed
            default: openness = .open
            }
        } else {
            openness = .all
        }

        var allPRs: [GitHubPullRequest] = []
        var page = 1
        let perPage = 100

        while true {
            let prs = try await octokitClient.listPullRequests(
                owner: owner,
                repository: repo,
                state: openness,
                sort: .created,
                direction: .desc,
                page: String(page),
                perPage: String(perPage)
            )

            if prs.isEmpty {
                break
            }

            let mapped = prs.map { $0.toGitHubPullRequest() }

            // If we have a since date, check if we've hit PRs older than it
            if let since = since {
                let formatter = ISO8601DateFormatter()
                var hitOldPRs = false

                for pr in mapped {
                    guard let createdStr = pr.createdAt,
                          let createdDate = formatter.date(from: createdStr) else {
                        allPRs.append(pr)
                        continue
                    }

                    if createdDate >= since {
                        allPRs.append(pr)
                    } else {
                        hitOldPRs = true
                        break
                    }
                }

                if hitOldPRs {
                    break
                }
            } else {
                allPRs.append(contentsOf: mapped)
            }

            // Stop if we've reached the limit
            if allPRs.count >= limit {
                break
            }

            // Stop if this page had fewer results than requested (last page)
            if prs.count < perPage {
                break
            }

            page += 1
        }

        let result = Array(allPRs.prefix(limit))

        // Post-filter by enhancedState when a specific state was requested
        if let state {
            return result.filter { $0.enhancedState == state }
        }
        return result
    }

    public func getRepository() async throws -> GitHubRepository {
        let repo = try await octokitClient.repository(owner: owner, name: self.repo)
        return repo.toGitHubRepository()
    }

    // MARK: - GraphQL Operations

    public func fetchBodyHTML(number: Int) async throws -> String {
        try await octokitClient.pullRequestBodyHTML(owner: owner, repository: repo, number: number)
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
