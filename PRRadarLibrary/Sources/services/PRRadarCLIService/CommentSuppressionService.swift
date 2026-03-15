import Foundation
import PRRadarModels

/// Applies per-rule-per-file comment limits to a reconciled list of review comments.
///
/// After reconciliation produces `[ReviewComment]`, this service decides which pending
/// comments are normal, which is the limiting comment, and which are suppressed.
/// The max comments per file is read from each comment's `maxCommentsPerFile` property,
/// which originates from the rule definition.
public struct CommentSuppressionService: Sendable {
    public init() {}

    /// Result of applying suppression to a review comment list.
    public struct SuppressionResult: Sendable {
        public let comments: [ReviewComment]
        public let suppressedCount: Int
    }

    /// Apply per-rule-per-file limits to reconciled comments.
    ///
    /// Each comment carries its rule's `maxCommentsPerFile` limit. Groups where no comment
    /// defines a limit (nil) are left unchanged.
    ///
    /// - Parameter comments: Reconciled review comments from `ViolationService.reconcile()`
    /// - Returns: The modified comment list with suppression roles applied to pending comments.
    public static func applySuppression(to comments: [ReviewComment]) -> SuppressionResult {
        // Group by (ruleName, filePath)
        var groups: [GroupKey: [Int]] = [:]
        for (index, comment) in comments.enumerated() {
            guard let ruleName = comment.ruleName else { continue }
            let key = GroupKey(ruleName: ruleName, filePath: comment.filePath)
            groups[key, default: []].append(index)
        }

        var result = comments
        var totalSuppressed = 0

        for (_, indices) in groups {
            let groupComments = indices.map { comments[$0] }

            // Read the max from the rule — use the first non-nil value in the group
            guard let max = groupComments.compactMap({ $0.pending?.maxCommentsPerFile }).first,
                  max > 0 else {
                continue
            }

            // Count already-posted non-suppressed comments (these count toward the limit)
            let postedCount = groupComments.filter { comment in
                switch comment.state {
                case .redetected, .postedOnly:
                    return true
                case .new, .needsUpdate:
                    return false
                }
            }.count

            // Collect pending comment indices, sorted by line number for deterministic ordering
            let pendingIndices = indices.filter { comments[$0].needsPosting }
                .sorted { a, b in
                    let lineA = comments[a].lineNumber ?? Int.max
                    let lineB = comments[b].lineNumber ?? Int.max
                    return lineA < lineB
                }

            guard !pendingIndices.isEmpty else { continue }

            let remaining = max - postedCount
            if remaining >= pendingIndices.count {
                continue
            }

            if remaining <= 0 {
                for idx in pendingIndices {
                    result[idx] = applySuppressedRole(to: result[idx])
                }
                totalSuppressed += pendingIndices.count
                continue
            }

            // remaining > 0 but < pendingIndices.count
            let limitingIndex = remaining - 1

            // The limiting comment
            let limitIdx = pendingIndices[limitingIndex]
            result[limitIdx] = applyLimitingRole(to: result[limitIdx])

            // Remaining are suppressed
            let suppressedIndices = pendingIndices[(limitingIndex + 1)...]
            for idx in suppressedIndices {
                result[idx] = applySuppressedRole(to: result[idx])
            }
            totalSuppressed += suppressedIndices.count
        }

        return SuppressionResult(comments: result, suppressedCount: totalSuppressed)
    }

    /// Count how many comments are suppressed in a given (ruleName, filePath) group
    /// for display in the limiting comment's visible text.
    public static func suppressedCount(
        in comments: [ReviewComment],
        ruleName: String,
        filePath: String
    ) -> Int {
        comments.filter {
            $0.ruleName == ruleName && $0.filePath == filePath && $0.isSuppressed
        }.count
    }

    // MARK: - Private

    private struct GroupKey: Hashable {
        let ruleName: String
        let filePath: String
    }

    private static func applySuppressedRole(to comment: ReviewComment) -> ReviewComment {
        guard let pending = comment.pending else { return comment }
        let suppressed = pending.withSuppression(role: .suppressed)
        switch comment {
        case .new:
            return .new(pending: suppressed)
        case .needsUpdate(_, let posted):
            return .needsUpdate(pending: suppressed, posted: posted)
        case .redetected, .postedOnly:
            return comment
        }
    }

    private static func applyLimitingRole(to comment: ReviewComment) -> ReviewComment {
        guard let pending = comment.pending else { return comment }
        let limiting = pending.withSuppression(role: .limiting)
        switch comment {
        case .new:
            return .new(pending: limiting)
        case .needsUpdate(_, let posted):
            return .needsUpdate(pending: limiting, posted: posted)
        case .redetected, .postedOnly:
            return comment
        }
    }
}
