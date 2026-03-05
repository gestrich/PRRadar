import Foundation

// MARK: - PR Filtering

public struct PRFilter: Sendable {
    public var dateFilter: PRDateFilter?
    public var state: PRState?

    public init(dateFilter: PRDateFilter? = nil, state: PRState? = nil) {
        self.dateFilter = dateFilter
        self.state = state
    }
}

public enum PRDateFilter: Sendable {
    case createdSince(Date)
    case updatedSince(Date)
    case mergedSince(Date)
    case closedSince(Date)

    public var date: Date {
        switch self {
        case .createdSince(let d), .updatedSince(let d),
             .mergedSince(let d), .closedSince(let d):
            return d
        }
    }

    public var fieldLabel: String {
        switch self {
        case .createdSince: return "created"
        case .updatedSince: return "updated"
        case .mergedSince: return "merged"
        case .closedSince: return "closed"
        }
    }

    public var sortsByCreated: Bool {
        switch self {
        case .createdSince: return true
        case .updatedSince, .mergedSince, .closedSince: return false
        }
    }

    public var requiresClosedAPIState: Bool {
        switch self {
        case .createdSince, .updatedSince: return false
        case .mergedSince, .closedSince: return true
        }
    }

    public var dateExtractor: @Sendable (GitHubPullRequest) -> String? {
        switch self {
        case .createdSince: return { $0.createdAt }
        case .updatedSince: return { $0.updatedAt }
        case .mergedSince: return { $0.mergedAt }
        case .closedSince: return { $0.closedAt }
        }
    }

    public var earlyStopExtractor: @Sendable (GitHubPullRequest) -> String? {
        switch self {
        case .createdSince: return { $0.createdAt }
        case .updatedSince, .mergedSince, .closedSince: return { $0.updatedAt }
        }
    }
}

// MARK: - PR State

public enum PRState: String, Codable, Sendable, CaseIterable {
    case open = "OPEN"
    case closed = "CLOSED"
    case merged = "MERGED"
    case draft = "DRAFT"
    
    public var displayName: String {
        switch self {
        case .open: return "Open"
        case .closed: return "Closed"
        case .merged: return "Merged"
        case .draft: return "Draft"
        }
    }
    
    public var filterValue: String {
        switch self {
        case .open, .draft: return "open"
        case .closed: return "closed"
        case .merged: return "merged"
        }
    }

    /// The GitHub API state parameter value. The API only accepts "open", "closed", or "all".
    /// Draft PRs are open with `isDraft=true`; merged PRs are closed with `mergedAt != nil`.
    public var apiStateValue: String {
        switch self {
        case .open, .draft: return "open"
        case .closed, .merged: return "closed"
        }
    }

    public static func fromCLIString(_ value: String) -> PRState? {
        switch value.lowercased() {
        case "open": return .open
        case "draft": return .draft
        case "closed": return .closed
        case "merged": return .merged
        default: return nil
        }
    }
}

public struct PRMetadata: Codable, Sendable, Identifiable, Hashable {
    public var id: Int { number }

    public let number: Int
    public var displayNumber: String { "#\(number)" }
    public let title: String
    public let body: String?
    public let author: Author
    public let state: String
    public let headRefName: String
    public let createdAt: String
    public let updatedAt: String?
    public let url: String?

    public init(
        number: Int,
        title: String,
        body: String? = nil,
        author: Author,
        state: String,
        headRefName: String,
        createdAt: String,
        updatedAt: String? = nil,
        url: String? = nil
    ) {
        self.number = number
        self.title = title
        self.body = body
        self.author = author
        self.state = state
        self.headRefName = headRefName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
    }

    public static func fallback(number: Int) -> PRMetadata {
        PRMetadata(
            number: number,
            title: "PR #\(number)",
            author: Author(login: "", name: ""),
            state: "",
            headRefName: "",
            createdAt: ""
        )
    }

    public struct Author: Codable, Sendable, Hashable {
        public let login: String
        public let name: String

        public init(login: String, name: String) {
            self.login = login
            self.name = name
        }
    }
}
