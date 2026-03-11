import Foundation

public enum ReviewComment: Sendable, Identifiable {
    case new(pending: PRComment)
    case redetected(pending: PRComment, posted: GitHubReviewComment)
    case needsUpdate(pending: PRComment, posted: GitHubReviewComment)
    case postedOnly(posted: GitHubReviewComment)

    public var id: String {
        switch self {
        case .new(let pending):
            return pending.id
        case .redetected(_, let posted), .needsUpdate(_, let posted):
            return "matched-\(posted.id)"
        case .postedOnly(let posted):
            return posted.id
        }
    }

    public enum State: Sendable, Equatable, Hashable {
        case new
        case redetected
        case needsUpdate
        case postedOnly
    }

    public var state: State {
        switch self {
        case .new: .new
        case .redetected: .redetected
        case .needsUpdate: .needsUpdate
        case .postedOnly: .postedOnly
        }
    }

    public var pending: PRComment? {
        switch self {
        case .new(let pending), .redetected(let pending, _), .needsUpdate(let pending, _):
            return pending
        case .postedOnly:
            return nil
        }
    }

    public var posted: GitHubReviewComment? {
        switch self {
        case .redetected(_, let posted), .needsUpdate(_, let posted), .postedOnly(let posted):
            return posted
        case .new:
            return nil
        }
    }

    public var filePath: String { pending?.filePath ?? posted?.path ?? "" }
    public var lineNumber: Int? { pending?.lineNumber ?? posted?.line }
    public var score: Int? { pending?.score }
    public var ruleName: String? { pending?.ruleName }

    public var needsPosting: Bool {
        switch self {
        case .new, .needsUpdate: true
        case .redetected, .postedOnly: false
        }
    }

    public var isPosted: Bool {
        switch self {
        case .redetected, .postedOnly: true
        case .new, .needsUpdate: false
        }
    }

    public var displayOrder: Int {
        switch self {
        case .postedOnly: 0
        case .redetected: 1
        case .needsUpdate: 2
        case .new: 3
        }
    }
}

extension [ReviewComment] {
    public func sortedByDisplayOrder() -> [ReviewComment] {
        sorted { $0.displayOrder < $1.displayOrder }
    }
}
