import Foundation
@preconcurrency import OctoKit

public enum OctokitClientError: Error, Sendable {
    case authenticationFailed
    case notFound(String)
    case rateLimitExceeded
    case requestFailed(String)
    case invalidResponse
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
