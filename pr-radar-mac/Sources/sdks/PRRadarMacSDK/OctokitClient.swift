import Foundation
@preconcurrency import OctoKit

public enum OctokitClientError: Error, Sendable {
    case authenticationFailed
    case notFound(String)
    case rateLimitExceeded
    case requestFailed(String)
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
