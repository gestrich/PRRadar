import Foundation

public struct ReviewComment: Sendable, Identifiable {
    public let pending: PRComment?
    public let posted: GitHubReviewComment?

    public init(pending: PRComment?, posted: GitHubReviewComment?) {
        self.pending = pending
        self.posted = posted
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
        case postedOnly
    }

    public var state: State {
        switch (pending, posted) {
        case (.some, .some): return .redetected
        case (.some, .none): return .new
        case (.none, .some): return .postedOnly
        case (.none, .none): return .postedOnly
        }
    }

    public var filePath: String { pending?.filePath ?? posted?.path ?? "" }
    public var lineNumber: Int? { pending?.lineNumber ?? posted?.line }
    public var score: Int? { pending?.score }
    public var ruleName: String? { pending?.ruleName }
}
