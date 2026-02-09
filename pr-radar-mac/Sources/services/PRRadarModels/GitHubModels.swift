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
        self.author = author
        self.labels = labels
        self.files = files
        self.commits = commits
    }

    public func toPRMetadata() -> PRMetadata {
        PRMetadata(
            number: number,
            title: title,
            author: PRMetadata.Author(
                login: author?.login ?? "",
                name: author?.name ?? ""
            ),
            state: state ?? "",
            headRefName: headRefName ?? "",
            createdAt: createdAt ?? ""
        )
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

    public init(
        id: String,
        body: String,
        path: String,
        line: Int? = nil,
        startLine: Int? = nil,
        author: GitHubAuthor? = nil,
        createdAt: String? = nil,
        url: String? = nil,
        inReplyToId: String? = nil
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
