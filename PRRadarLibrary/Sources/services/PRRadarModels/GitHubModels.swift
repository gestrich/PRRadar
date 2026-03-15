import Foundation

// MARK: - GitHub API Response Models

public struct GitHubAuthor: Codable, Sendable {
    public let login: String
    public let id: String?
    public let name: String?

    public init(login: String, id: String? = nil, name: String? = nil) {
        self.login = login
        self.id = id
        self.name = name
    }
}

public struct GitHubLabel: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let color: String?

    public init(id: String, name: String, description: String? = nil, color: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.color = color
    }
}

public struct GitHubFile: Codable, Sendable {
    public let path: String
    public let additions: Int
    public let deletions: Int

    public init(path: String, additions: Int = 0, deletions: Int = 0) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
    }
}

public struct GitHubCommit: Codable, Sendable {
    public let oid: String
    public let messageHeadline: String?
    public let messageBody: String?
    public let authoredDate: String?
    public let committedDate: String?

    public init(
        oid: String,
        messageHeadline: String? = nil,
        messageBody: String? = nil,
        authoredDate: String? = nil,
        committedDate: String? = nil
    ) {
        self.oid = oid
        self.messageHeadline = messageHeadline
        self.messageBody = messageBody
        self.authoredDate = authoredDate
        self.committedDate = committedDate
    }
}

public struct GitHubComment: Codable, Sendable {
    public let id: String
    public let body: String
    public let author: GitHubAuthor?
    public let createdAt: String?
    public let url: String?

    public init(
        id: String,
        body: String,
        author: GitHubAuthor? = nil,
        createdAt: String? = nil,
        url: String? = nil
    ) {
        self.id = id
        self.body = body
        self.author = author
        self.createdAt = createdAt
        self.url = url
    }
}

public struct GitHubReview: Codable, Sendable {
    public let id: String
    public let body: String
    public let state: String?
    public let author: GitHubAuthor?
    public let submittedAt: String?

    public init(
        id: String,
        body: String,
        state: String? = nil,
        author: GitHubAuthor? = nil,
        submittedAt: String? = nil
    ) {
        self.id = id
        self.body = body
        self.state = state
        self.author = author
        self.submittedAt = submittedAt
    }
}

public struct GitHubOwner: Codable, Sendable {
    public let login: String
    public let id: String?

    public init(login: String, id: String? = nil) {
        self.login = login
        self.id = id
    }
}

public struct GitHubDefaultBranchRef: Codable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

// MARK: - Pull Request

public struct GitHubPullRequest: Codable, Sendable {
    public let number: Int
    public let title: String
    public let body: String?
    public let state: String?
    public let isDraft: Bool?
    public let url: String?
    public let baseRefName: String?
    public let headRefName: String?
    public let headRefOid: String?
    public let additions: Int?
    public let deletions: Int?
    public let changedFiles: Int?
    public let createdAt: String?
    public let updatedAt: String?
    public let mergedAt: String?
    public let closedAt: String?
    public let author: GitHubAuthor?
    public let labels: [GitHubLabel]?
    public let files: [GitHubFile]?
    public let commits: [GitHubCommit]?

    public init(
        number: Int,
        title: String,
        body: String? = nil,
        state: String? = nil,
        isDraft: Bool? = nil,
        url: String? = nil,
        baseRefName: String? = nil,
        headRefName: String? = nil,
        headRefOid: String? = nil,
        additions: Int? = nil,
        deletions: Int? = nil,
        changedFiles: Int? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        mergedAt: String? = nil,
        closedAt: String? = nil,
        author: GitHubAuthor? = nil,
        labels: [GitHubLabel]? = nil,
        files: [GitHubFile]? = nil,
        commits: [GitHubCommit]? = nil
    ) {
        self.number = number
        self.title = title
        self.body = body
        self.state = state
        self.isDraft = isDraft
        self.url = url
        self.baseRefName = baseRefName
        self.headRefName = headRefName
        self.headRefOid = headRefOid
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mergedAt = mergedAt
        self.closedAt = closedAt
        self.author = author
        self.labels = labels
        self.files = files
        self.commits = commits
    }

    public var enhancedState: PRState {
        switch (state ?? "").lowercased() {
        case "open":
            return (isDraft == true) ? .draft : .open
        case "closed":
            return (mergedAt != nil) ? .merged : .closed
        default:
            return .open
        }
    }

    public func toPRMetadata() throws -> PRMetadata {
        guard let login = author?.login else {
            throw PRMetadataConversionError.missingField("author.login", prNumber: number)
        }
        guard let headRefName else {
            throw PRMetadataConversionError.missingField("headRefName", prNumber: number)
        }
        guard let baseRefName else {
            throw PRMetadataConversionError.missingField("baseRefName", prNumber: number)
        }
        guard let createdAt else {
            throw PRMetadataConversionError.missingField("createdAt", prNumber: number)
        }
        return PRMetadata(
            number: number,
            title: title,
            body: body,
            author: PRMetadata.Author(
                login: login,
                name: author?.name ?? ""
            ),
            state: enhancedState.rawValue,
            headRefName: headRefName,
            baseRefName: baseRefName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            mergedAt: mergedAt,
            closedAt: closedAt,
            url: url
        )
    }
}

extension GitHubPullRequest: DateFilterable {
    public func dateField(_ field: PRDateField) -> String? {
        switch field {
        case .created: return createdAt
        case .updated: return updatedAt
        case .merged: return mergedAt
        case .closed: return closedAt
        }
    }
}

public enum PRMetadataConversionError: Error, LocalizedError {
    case missingField(String, prNumber: Int)

    public var errorDescription: String? {
        switch self {
        case .missingField(let field, let prNumber):
            return "PR #\(prNumber): missing required field '\(field)'"
        }
    }
}

// MARK: - Review Comments (inline code comments with path/line)

public struct GitHubReviewComment: Codable, Sendable, Identifiable {
    public let id: String
    public let body: String
    public let path: String
    public let line: Int?
    public let startLine: Int?
    public let author: GitHubAuthor?
    public let createdAt: String?
    public let url: String?
    public let inReplyToId: String?
    public let isResolved: Bool
    public let isOutdated: Bool

    public var metadata: CommentMetadata? {
        CommentMetadata.parse(from: body)
    }

    public var bodyWithoutMetadata: String {
        CommentMetadata.stripMetadata(from: body)
    }

    public var metadataLine: Int? {
        metadata?.fileInfo?.line
    }

    public var metadataBlobSHA: String? {
        guard let sha = metadata?.fileInfo?.blobSHA, !sha.isEmpty else { return nil }
        return sha
    }

    public init(
        id: String,
        body: String,
        path: String,
        line: Int? = nil,
        startLine: Int? = nil,
        author: GitHubAuthor? = nil,
        createdAt: String? = nil,
        url: String? = nil,
        inReplyToId: String? = nil,
        isResolved: Bool = false,
        isOutdated: Bool = false
    ) {
        self.id = id
        self.body = body
        self.path = path
        self.line = line
        self.startLine = startLine
        self.author = author
        self.createdAt = createdAt
        self.url = url
        self.inReplyToId = inReplyToId
        self.isResolved = isResolved
        self.isOutdated = isOutdated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        path = try container.decode(String.self, forKey: .path)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        startLine = try container.decodeIfPresent(Int.self, forKey: .startLine)
        author = try container.decodeIfPresent(GitHubAuthor.self, forKey: .author)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        inReplyToId = try container.decodeIfPresent(String.self, forKey: .inReplyToId)
        isResolved = try container.decodeIfPresent(Bool.self, forKey: .isResolved) ?? false
        isOutdated = try container.decodeIfPresent(Bool.self, forKey: .isOutdated) ?? false
    }
}

extension GitHubReviewComment {
    public func withResolution(_ resolved: Bool) -> GitHubReviewComment {
        GitHubReviewComment(
            id: id,
            body: body,
            path: path,
            line: line,
            startLine: startLine,
            author: author,
            createdAt: createdAt,
            url: url,
            inReplyToId: inReplyToId,
            isResolved: resolved,
            isOutdated: isOutdated
        )
    }
}

// MARK: - Pull Request Comments

public struct GitHubPullRequestComments: Codable, Sendable {
    public let comments: [GitHubComment]
    public let reviews: [GitHubReview]
    public let reviewComments: [GitHubReviewComment]

    public init(
        comments: [GitHubComment] = [],
        reviews: [GitHubReview] = [],
        reviewComments: [GitHubReviewComment] = []
    ) {
        self.comments = comments
        self.reviews = reviews
        self.reviewComments = reviewComments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comments = try container.decode([GitHubComment].self, forKey: .comments)
        reviews = try container.decode([GitHubReview].self, forKey: .reviews)
        reviewComments = try container.decodeIfPresent([GitHubReviewComment].self, forKey: .reviewComments) ?? []
    }
}

extension GitHubPullRequestComments {
    /// Enriches review comments with thread resolution status.
    ///
    /// - Parameter resolvedCommentIDs: Set of review comment IDs whose threads are resolved
    /// - Returns: A copy with `isResolved` set on matching review comments
    public func withReviewThreadResolution(resolvedCommentIDs: Set<String>) -> GitHubPullRequestComments {
        guard !resolvedCommentIDs.isEmpty else { return self }
        return GitHubPullRequestComments(
            comments: comments,
            reviews: reviews,
            reviewComments: reviewComments.map { rc in
                resolvedCommentIDs.contains(rc.id) ? rc.withResolution(true) : rc
            }
        )
    }
}

// MARK: - Repository

public struct GitHubRepository: Codable, Sendable {
    public let name: String
    public let url: String?
    public let owner: GitHubOwner?
    public let defaultBranchRef: GitHubDefaultBranchRef?

    public init(
        name: String,
        url: String? = nil,
        owner: GitHubOwner? = nil,
        defaultBranchRef: GitHubDefaultBranchRef? = nil
    ) {
        self.name = name
        self.url = url
        self.owner = owner
        self.defaultBranchRef = defaultBranchRef
    }

    public var ownerLogin: String {
        owner?.login ?? ""
    }

    public var defaultBranch: String {
        defaultBranchRef?.name ?? ""
    }

    public var fullName: String {
        if let owner {
            return "\(owner.login)/\(name)"
        }
        return name
    }
}

// MARK: - Author Name Enrichment

extension GitHubAuthor {
    public func withName(from nameMap: [String: String]) -> GitHubAuthor {
        guard let resolved = nameMap[login], name == nil || name?.isEmpty == true else {
            return self
        }
        return GitHubAuthor(login: login, id: id, name: resolved)
    }
}

extension GitHubPullRequest {
    public func withAuthorNames(from nameMap: [String: String]) -> GitHubPullRequest {
        GitHubPullRequest(
            number: number,
            title: title,
            body: body,
            state: state,
            isDraft: isDraft,
            url: url,
            baseRefName: baseRefName,
            headRefName: headRefName,
            headRefOid: headRefOid,
            additions: additions,
            deletions: deletions,
            changedFiles: changedFiles,
            createdAt: createdAt,
            updatedAt: updatedAt,
            mergedAt: mergedAt,
            closedAt: closedAt,
            author: author?.withName(from: nameMap),
            labels: labels,
            files: files,
            commits: commits
        )
    }
}

extension GitHubPullRequestComments {
    public func withAuthorNames(from nameMap: [String: String]) -> GitHubPullRequestComments {
        GitHubPullRequestComments(
            comments: comments.map { c in
                GitHubComment(
                    id: c.id,
                    body: c.body,
                    author: c.author?.withName(from: nameMap),
                    createdAt: c.createdAt,
                    url: c.url
                )
            },
            reviews: reviews.map { r in
                GitHubReview(
                    id: r.id,
                    body: r.body,
                    state: r.state,
                    author: r.author?.withName(from: nameMap),
                    submittedAt: r.submittedAt
                )
            },
            reviewComments: reviewComments.map { rc in
                GitHubReviewComment(
                    id: rc.id,
                    body: rc.body,
                    path: rc.path,
                    line: rc.line,
                    startLine: rc.startLine,
                    author: rc.author?.withName(from: nameMap),
                    createdAt: rc.createdAt,
                    url: rc.url,
                    inReplyToId: rc.inReplyToId,
                    isResolved: rc.isResolved,
                    isOutdated: rc.isOutdated
                )
            }
        )
    }
}
