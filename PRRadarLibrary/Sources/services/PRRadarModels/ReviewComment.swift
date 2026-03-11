import Foundation

public struct ReviewComment: Sendable, Identifiable {
    public let pending: PRComment?
    public let posted: GitHubReviewComment?
    public let state: State

    public init(pending: PRComment?, posted: GitHubReviewComment?, state: State) {
        self.pending = pending
        self.posted = posted
        self.state = state
    }

    public var id: String {
        switch (pending, posted) {
        case let (.some(_), .some(posted)):
            return "matched-\(posted.id)"
        case let (.some(pending), .none):
            return pending.id
        case let (.none, .some(posted)):
            return posted.id
        case (.none, .none):
            return UUID().uuidString
        }
    }

    public enum State: Sendable {
        case new
        case redetected
        case needsUpdate
        case postedOnly
    }

    public var filePath: String { pending?.filePath ?? posted?.path ?? "" }
    public var lineNumber: Int? { pending?.lineNumber ?? posted?.line }
    public var score: Int? { pending?.score }
    public var ruleName: String? { pending?.ruleName }
}
