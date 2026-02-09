import Foundation

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
