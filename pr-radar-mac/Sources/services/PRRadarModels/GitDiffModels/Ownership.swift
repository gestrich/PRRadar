import Foundation

public struct Ownership: Codable, Sendable {
    public let author: GitAuthor
    public let commitHash: String
    public let summary: String
    public let commitDate: String?
    public let confidence: String

    public init(author: GitAuthor, commitHash: String, summary: String, commitDate: String?, confidence: String) {
        self.author = author
        self.commitHash = commitHash
        self.summary = summary
        self.commitDate = commitDate
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case author
        case commitHash = "commit_hash"
        case summary
        case commitDate = "commit_date"
        case confidence
    }
}
