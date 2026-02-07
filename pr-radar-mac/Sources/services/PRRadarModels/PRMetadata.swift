import Foundation

public struct PRMetadata: Codable, Sendable, Identifiable, Hashable {
    public var id: Int { number }

    public let number: Int
    public let title: String
    public let author: Author
    public let state: String
    public let headRefName: String
    public let createdAt: String

    public struct Author: Codable, Sendable, Hashable {
        public let login: String
        public let name: String

        public init(login: String, name: String) {
            self.login = login
            self.name = name
        }
    }

    public init(
        number: Int,
        title: String,
        author: Author,
        state: String,
        headRefName: String,
        createdAt: String
    ) {
        self.number = number
        self.title = title
        self.author = author
        self.state = state
        self.headRefName = headRefName
        self.createdAt = createdAt
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
}
