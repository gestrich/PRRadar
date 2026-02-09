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

// MARK: - GitHub API Model Mismatch Workaround
//
// **Problem**: GitHub's REST API omits the `patch` field for certain file types:
//   - Files with `status: "renamed"` and `changes: 0` (pure renames, no content changes)
//   - Binary files
//   - Files that are too large for diff generation
//
// **OctoKit Bug**: The OctoKit library's `PullRequest.File` model defines `patch` as a
// non-optional `String`, which doesn't match GitHub's actual API behavior. This causes
// JSON decoding to fail with `keyNotFound: "patch"` errors when processing PRs that
// contain renamed files.
//
// **Why We Can't Fix This Properly**:
//   1. OctoKit is a third-party dependency - we can't modify its source
//   2. `PullRequest.File` is a public struct without a public initializer
//   3. Filing a PR to fix OctoKit would take time and may not be accepted
//
// **This Workaround**:
//   1. Define a custom `PullRequestFile` struct with an optional `patch` field
//   2. Decode GitHub's JSON using our custom model (which handles missing patches)
//   3. Convert to OctoKit's model via JSON round-tripping (encode dict → decode File)
//   4. Use empty string for missing patches (maintains compatibility with existing code)
//
// **Tested With**: PR #18729 and #18725 in ff-ios repo (both contain renamed files)
//
// **Future**: If OctoKit fixes this issue upstream, we can remove this workaround
// and use their `listPullRequestsFiles()` method directly.
//
private struct PullRequestFile: Codable {
    var sha: String
    var filename: String
    var status: PullRequest.File.Status
    var additions: Int
    var deletions: Int
    var changes: Int
    var blobUrl: String
    var rawUrl: String
    var contentsUrl: String
    var patch: String?  // Optional to handle GitHub's actual API behavior
    
    enum CodingKeys: String, CodingKey {
        case sha, filename, status, additions, deletions, changes, patch
        case blobUrl = "blob_url"
        case rawUrl = "raw_url"
        case contentsUrl = "contents_url"
    }
    
    /// Converts to OctoKit's `PullRequest.File` model via JSON round-tripping.
    ///
    /// This is necessary because `PullRequest.File` doesn't have a public initializer.
    /// We serialize to a dictionary with all required fields (using empty string for
    /// missing patches), then decode it using OctoKit's Codable implementation.
    ///
    /// - Returns: An OctoKit `PullRequest.File` instance
    func toOctokitFile() -> PullRequest.File {
        let dict: [String: Any] = [
            "sha": sha,
            "filename": filename,
            "status": status.rawValue,
            "additions": additions,
            "deletions": deletions,
            "changes": changes,
            "blob_url": blobUrl,
            "raw_url": rawUrl,
            "contents_url": contentsUrl,
            "patch": patch ?? ""  // Empty string for renamed files without content changes
        ]
        
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        return try! decoder.decode(PullRequest.File.self, from: data)
    }
}

private struct ReviewCommentResponse: Codable {
    let id: Int
    let body: String
    let path: String
    let line: Int?
    let startLine: Int?
    let createdAt: String?
    let htmlUrl: String?
    let inReplyToId: Int?
    let user: ReviewCommentUser?

    struct ReviewCommentUser: Codable {
        let login: String
        let id: Int
    }

    enum CodingKeys: String, CodingKey {
        case id, body, path, line, user
        case startLine = "start_line"
        case createdAt = "created_at"
        case htmlUrl = "html_url"
        case inReplyToId = "in_reply_to_id"
    }
}

public struct ReviewCommentData: Sendable {
    public let id: Int
    public let body: String
    public let path: String
    public let line: Int?
    public let startLine: Int?
    public let createdAt: String?
    public let htmlUrl: String?
    public let inReplyToId: Int?
    public let userLogin: String?
    public let userId: Int?
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
        sort: SortType = .created,
        direction: SortDirection = .desc,
        page: String? = nil,
        perPage: String? = nil
    ) async throws -> [PullRequest] {
        try await client().pullRequests(
            owner: owner,
            repository: repository,
            state: state,
            sort: sort,
            page: page,
            perPage: perPage,
            direction: direction
        )
    }

    /// Fetches the list of files changed in a pull request.
    ///
    /// **Implementation Note**: This method bypasses OctoKit's `listPullRequestsFiles()`
    /// because that method uses a model with a non-optional `patch` field that doesn't
    /// match GitHub's actual API behavior. See the `PullRequestFile` struct documentation
    /// above for the full explanation of why this workaround is necessary.
    ///
    /// - Parameters:
    ///   - owner: The repository owner
    ///   - repository: The repository name
    ///   - number: The pull request number
    /// - Returns: Array of file objects, with empty string for patches that GitHub omits
    /// - Throws: `OctokitClientError` for authentication, network, or API errors
    public func listPullRequestFiles(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> [PullRequest.File] {
        let baseURL = apiEndpoint ?? "https://api.github.com"
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repository)/pulls/\(number)/files")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Decode using our custom model that handles optional patch field
            let customFiles = try decoder.decode([PullRequestFile].self, from: data)
            
            // Convert to OctoKit's model (see PullRequestFile.toOctokitFile() for details)
            return customFiles.map { $0.toOctokitFile() }
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("Pull request \(number) files not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    public func listPullRequestReviewComments(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> [ReviewCommentData] {
        let baseURL = apiEndpoint ?? "https://api.github.com"
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repository)/pulls/\(number)/comments")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let responses = try decoder.decode([ReviewCommentResponse].self, from: data)
            return responses.map { r in
                ReviewCommentData(
                    id: r.id,
                    body: r.body,
                    path: r.path,
                    line: r.line,
                    startLine: r.startLine,
                    createdAt: r.createdAt,
                    htmlUrl: r.htmlUrl,
                    inReplyToId: r.inReplyToId,
                    userLogin: r.user?.login,
                    userId: r.user?.id
                )
            }
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("Pull request \(number) review comments not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
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
