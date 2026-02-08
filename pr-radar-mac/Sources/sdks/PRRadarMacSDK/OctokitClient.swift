import Foundation
@preconcurrency import OctoKit

public enum OctokitClientError: Error, Sendable, LocalizedError {
    case authenticationFailed
    case notFound(String)
    case rateLimitExceeded
    case requestFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "GitHub authentication failed. Check your token is valid."
        case .notFound(let detail):
            return "GitHub resource not found: \(detail)"
        case .rateLimitExceeded:
            return "GitHub API rate limit exceeded or access forbidden. Check your token permissions."
        case .requestFailed(let detail):
            return "GitHub API request failed: \(detail)"
        case .invalidResponse:
            return "Received an invalid response from GitHub API."
        }
    }
}

public struct OctokitClient: Sendable {
    private let token: String
    private let apiEndpoint: String?

    public init(token: String) {
        self.token = token
        self.apiEndpoint = nil
    }

    public init(token: String, enterpriseURL: String) {
        self.token = token
        self.apiEndpoint = enterpriseURL
    }

    // MARK: - Pull Request Operations

    public func pullRequest(owner: String, repository: String, number: Int) async throws -> PullRequest {
        try await client().pullRequest(owner: owner, repository: repository, number: number)
    }

    public func listPullRequests(
        owner: String,
        repository: String,
        state: Openness = .open,
        page: String? = nil,
        perPage: String? = nil
    ) async throws -> [PullRequest] {
        try await client().pullRequests(
            owner: owner,
            repository: repository,
            state: state,
            page: page,
            perPage: perPage
        )
    }

    public func listPullRequestFiles(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> [PullRequest.File] {
        try await client().listPullRequestsFiles(
            owner: owner,
            repository: repository,
            number: number
        )
    }

    public func getPullRequestDiff(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> String {
        let baseURL = apiEndpoint ?? "https://api.github.com"
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repository)/pulls/\(number)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3.diff", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            guard let diff = String(data: data, encoding: .utf8) else {
                throw OctokitClientError.invalidResponse
            }
            return diff
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("Pull request \(number) not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - Repository Operations

    public func repository(owner: String, name: String) async throws -> OctoKit.Repository {
        try await client().repository(owner: owner, name: name)
    }

    // MARK: - Comment Operations

    public func postIssueComment(
        owner: String,
        repository: String,
        number: Int,
        body: String
    ) async throws -> Issue.Comment {
        try await client().commentIssue(owner: owner, repository: repository, number: number, body: body)
    }

    @discardableResult
    public func postReviewComment(
        owner: String,
        repository: String,
        number: Int,
        commitId: String,
        path: String,
        line: Int,
        body: String
    ) async throws -> PullRequest.Comment {
        try await client().createPullRequestReviewComment(
            owner: owner,
            repository: repository,
            number: number,
            commitId: commitId,
            path: path,
            line: line,
            body: body
        )
    }

    public func issueComments(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> [Issue.Comment] {
        try await client().issueComments(owner: owner, repository: repository, number: number)
    }

    public func listReviews(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> [Review] {
        try await client().reviews(owner: owner, repository: repository, pullRequestNumber: number)
    }

    public func getPullRequestHeadSHA(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> String {
        let pr = try await pullRequest(owner: owner, repository: repository, number: number)
        guard let sha = pr.head?.sha else {
            throw OctokitClientError.requestFailed("Pull request \(number) has no head SHA")
        }
        return sha
    }

    // MARK: - Private

    private func client() -> Octokit {
        let config: TokenConfiguration
        if let apiEndpoint {
            config = TokenConfiguration(token, url: apiEndpoint)
        } else {
            config = TokenConfiguration(token)
        }
        return Octokit(config)
    }
}
