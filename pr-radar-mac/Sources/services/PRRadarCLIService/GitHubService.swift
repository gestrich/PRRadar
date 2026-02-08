import CLISDK
import Foundation
import PRRadarMacSDK
import PRRadarModels

public struct GitHubService: Sendable {
    private let client: CLIClient

    private static let prFields = [
        "number", "title", "body", "author",
        "baseRefName", "headRefName", "headRefOid",
        "state", "isDraft", "url",
        "createdAt", "updatedAt",
        "additions", "deletions", "changedFiles",
        "commits", "labels", "files",
    ]

    private static let prListFields = [
        "number", "title", "body", "author",
        "baseRefName", "headRefName", "headRefOid",
        "state", "isDraft", "url",
        "createdAt", "updatedAt",
        "additions", "deletions", "changedFiles",
        "labels",
    ]

    private static let prCommentFields = ["comments", "reviews"]

    private static let repoFields = ["name", "owner", "url", "defaultBranchRef"]

    public init(client: CLIClient) {
        self.client = client
    }

    // MARK: - Pull Request Operations

    public func getPRDiff(number: Int, repoPath: String) async throws -> String {
        try await client.execute(
            GhCLI.Pr.Diff(number: String(number)),
            workingDirectory: repoPath,
            printCommand: false
        )
    }

    public func getPullRequest(number: Int, repoPath: String) async throws -> GitHubPullRequest {
        let output = try await client.execute(
            GhCLI.Pr.View(number: String(number), json: Self.prFields.joined(separator: ",")),
            workingDirectory: repoPath,
            printCommand: false
        )
        return try JSONDecoder().decode(GitHubPullRequest.self, from: Data(output.utf8))
    }

    public func getPullRequestComments(number: Int, repoPath: String) async throws -> GitHubPullRequestComments {
        let output = try await client.execute(
            GhCLI.Pr.View(number: String(number), json: Self.prCommentFields.joined(separator: ",")),
            workingDirectory: repoPath,
            printCommand: false
        )
        return try JSONDecoder().decode(GitHubPullRequestComments.self, from: Data(output.utf8))
    }

    public func listPullRequests(
        limit: Int,
        state: String,
        repo: String? = nil,
        search: String? = nil,
        repoPath: String
    ) async throws -> [GitHubPullRequest] {
        let output = try await client.execute(
            GhCLI.Pr.List(
                json: Self.prListFields.joined(separator: ","),
                limit: String(limit),
                state: state,
                repo: repo,
                search: search
            ),
            workingDirectory: repoPath,
            printCommand: false
        )
        return try JSONDecoder().decode([GitHubPullRequest].self, from: Data(output.utf8))
    }

    public func getRepository(repo: String? = nil, repoPath: String) async throws -> GitHubRepository {
        let output = try await client.execute(
            GhCLI.Repo.View(repo: repo, json: Self.repoFields.joined(separator: ",")),
            workingDirectory: repoPath,
            printCommand: false
        )
        return try JSONDecoder().decode(GitHubRepository.self, from: Data(output.utf8))
    }

    // MARK: - API Operations

    public func apiGet(endpoint: String, jq: String? = nil, repoPath: String) async throws -> String {
        try await client.execute(
            GhCLI.Api(endpoint: endpoint, jq: jq),
            workingDirectory: repoPath,
            printCommand: false
        )
    }

    public func apiPost(endpoint: String, fields: [String: String], repoPath: String) async throws -> String {
        let fieldArgs = fields.map { "\($0.key)=\($0.value)" }
        return try await client.execute(
            GhCLI.Api(endpoint: endpoint, fields: fieldArgs),
            workingDirectory: repoPath,
            printCommand: false
        )
    }

    public func apiPostWithInt(
        endpoint: String,
        stringFields: [String: String],
        intFields: [String: Int],
        repoPath: String
    ) async throws -> String {
        let fArgs = stringFields.map { "\($0.key)=\($0.value)" }
        let rawArgs = intFields.map { "\($0.key)=\($0.value)" }
        return try await client.execute(
            GhCLI.Api(endpoint: endpoint, fields: fArgs, rawFields: rawArgs),
            workingDirectory: repoPath,
            printCommand: false
        )
    }

    public func apiPatch(endpoint: String, fields: [String: String], repoPath: String) async throws -> String {
        let fieldArgs = fields.map { "\($0.key)=\($0.value)" }
        return try await client.execute(
            GhCLI.Api(endpoint: endpoint, method: "PATCH", fields: fieldArgs),
            workingDirectory: repoPath,
            printCommand: false
        )
    }
}
