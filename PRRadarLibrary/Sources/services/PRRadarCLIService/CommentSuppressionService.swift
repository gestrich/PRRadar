import Foundation
import PRRadarModels

/// Applies per-rule-per-file comment limits to a reconciled list of review comments.
///
/// After reconciliation produces `[ReviewComment]`, this service decides which pending
/// comments are normal, which is the limiting comment, and which are suppressed.
public struct CommentSuppressionService: Sendable {
    public init() {}

    /// Result of applying suppression to a review comment list.
    public struct SuppressionResult: Sendable {
        public let comments: [ReviewComment]
        public let suppressedCount: Int
    }

    /// Apply per-rule-per-file limits to reconciled comments.
    ///
    /// - Parameters:
    ///   - comments: Reconciled review comments from `ViolationService.reconcile()`
    ///   - maxPerRulePerFile: Maximum comments to post per (ruleName, filePath) group.
    ///     Pass `nil` for unlimited (no suppression).
    /// - Returns: The modified comment list with suppression roles applied to pending comments.
    public static func applySuppression(
        to comments: [ReviewComment],
        maxPerRulePerFile: Int?
    ) -> SuppressionResult {
        guard let max = maxPerRulePerFile, max > 0 else {
            return SuppressionResult(comments: comments, suppressedCount: 0)
        }

        // Group by (ruleName, filePath) — only groups with pending comments need processing
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
                // Under limit — no suppression needed
                continue
            }

            if remaining <= 0 {
                // All pending comments are suppressed
                for idx in pendingIndices {
                    result[idx] = applySuppressedRole(to: result[idx])
                }
                totalSuppressed += pendingIndices.count
                continue
            }

            // remaining > 0 but < pendingIndices.count
            let normalCount = remaining - 1
            let limitingIndex = remaining - 1

            // First (remaining - 1) are normal — no suppression role needed

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

    /// Count how many comments would be suppressed in a given (ruleName, filePath) group
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
