import Foundation
import PRRadarConfigService
import PRRadarModels

/// Pure transformation service for converting evaluation results into PRComment instances.
public struct ViolationService: Sendable {
    public init() {}

    /// Filter evaluation results by violation status and score, converting to PRComment instances.
    public static func filterByScore(
        results: [RuleOutcome],
        tasks: [RuleRequest],
        minScore: Int
    ) -> [PRComment] {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
        var comments: [PRComment] = []

        for result in results {
            guard let task = taskMap[result.taskId] else { continue }
            comments.append(contentsOf: result.violationComments(task: task)
                .filter { $0.score >= minScore })
        }

        return comments
    }

    /// Load violations from evaluation result files on disk.
    public static func loadViolations(
        evaluationsDir: String,
        tasksDir: String,
        minScore: Int
    ) -> [PRComment] {
        let fm = FileManager.default
        var comments: [PRComment] = []

        // Load task metadata
        var taskMetadata: [String: RuleRequest] = [:]
        if let taskFiles = try? fm.contentsOfDirectory(atPath: tasksDir) {
            for file in taskFiles where file.hasPrefix(DataPathsService.dataFilePrefix) {
                let path = "\(tasksDir)/\(file)"
                guard let data = fm.contents(atPath: path),
                      let task = try? JSONDecoder().decode(RuleRequest.self, from: data) else { continue }
                taskMetadata[task.taskId] = task
            }
        }

        guard let evalFiles = try? fm.contentsOfDirectory(atPath: evaluationsDir) else { return comments }

        for file in evalFiles where file.hasPrefix(DataPathsService.dataFilePrefix) {
            let path = "\(evaluationsDir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let result = try? JSONDecoder().decode(RuleOutcome.self, from: data) else { continue }

            guard let task = taskMetadata[result.taskId] else { continue }
            comments.append(contentsOf: result.violationComments(task: task)
                .filter { $0.score >= minScore })
        }

        return comments
    }

    /// Match pending violations against posted GitHub review comments to produce a unified list.
    ///
    /// Uses metadata-aware matching for v1 comments (with embedded `<!-- prradar:v1 ... -->` blocks)
    /// and falls back to legacy heuristic matching for v0 comments (no metadata).
    ///
    /// Matching tiers for v1 comments:
    /// 1. Exact match (same rule_id + file + line), same body → `.redetected`
    /// 2. Exact match, different body → `.needsUpdate`
    /// 3. Line-shifted (same rule_id + file + fileBlobSHA, different line) → `.redetected`
    /// 4. File-changed (same rule_id + file, different fileBlobSHA) → `.new`
    ///
    /// Legacy v0 comments matched by file + line + body.contains(ruleName) always become `.needsUpdate`.
    public static func reconcile(
        pending: [PRComment],
        posted: [GitHubReviewComment]
    ) -> [ReviewComment] {
        // Partition posted comments into v1 (has metadata) and v0 (legacy)
        var v1Comments: [GitHubReviewComment] = []
        var v0Comments: [GitHubReviewComment] = []
        for comment in posted {
            if comment.metadata != nil {
                v1Comments.append(comment)
            } else {
                v0Comments.append(comment)
            }
        }

        // Index v1 comments by (ruleId, filePath) for efficient lookup
        var v1ByRuleAndFile: [String: [String: [GitHubReviewComment]]] = [:]
        for comment in v1Comments {
            guard let meta = comment.metadata else { continue }
            let ruleId = meta.rule.id
            let file = meta.fileInfo?.path ?? comment.path
            v1ByRuleAndFile[ruleId, default: [:]][file, default: []].append(comment)
        }

        // Index v0 comments by (filePath, lineNumber) for legacy matching
        var v0ByFileAndLine: [String: [Int?: [GitHubReviewComment]]] = [:]
        for comment in v0Comments {
            v0ByFileAndLine[comment.path, default: [:]][comment.line, default: []].append(comment)
        }

        // Track consumed posted comments to avoid double-matching
        var consumedIds: Set<String> = []
        var results: [ReviewComment] = []

        for p in pending {
            // Try v1 metadata-aware matching first
            if let match = matchV1(pending: p, index: &v1ByRuleAndFile, consumedIds: &consumedIds) {
                results.append(match)
                continue
            }

            // Fall back to v0 legacy matching
            if let match = matchV0(pending: p, index: &v0ByFileAndLine, consumedIds: &consumedIds) {
                results.append(match)
                continue
            }

            // No match — new violation
            results.append(.new(pending: p))
        }

        // Remaining unmatched posted comments
        for comment in posted where !consumedIds.contains(comment.id) {
            results.append(.postedOnly(posted: comment))
        }

        return results
    }

    // MARK: - Private Matching

    /// Try to match a pending violation against v1 (metadata-bearing) posted comments.
    private static func matchV1(
        pending: PRComment,
        index: inout [String: [String: [GitHubReviewComment]]],
        consumedIds: inout Set<String>
    ) -> ReviewComment? {
        let ruleId = pending.ruleName
        let file = pending.filePath

        guard let candidates = index[ruleId]?[file]?.filter({ !consumedIds.contains($0.id) }),
              !candidates.isEmpty else {
            return nil
        }

        let pendingBody = pending.toGitHubMarkdown()

        // Tier 1 & 2: Exact match on rule_id + file + line
        if let exactMatch = candidates.first(where: { candidate in
            guard let meta = candidate.metadata else { return false }
            return meta.fileInfo?.line == pending.lineNumber
        }) {
            consumedIds.insert(exactMatch.id)
            let postedBody = exactMatch.bodyWithoutMetadata
            if pendingBody == postedBody {
                return .redetected(pending: pending, posted: exactMatch)
            } else {
                return .needsUpdate(pending: pending, posted: exactMatch)
            }
        }

        // Tier 3: Line-shifted match — same fileBlobSHA means file content unchanged, line just moved
        if let pendingBlobSHA = pending.fileBlobSHA, !pendingBlobSHA.isEmpty {
            if let shiftedMatch = candidates.first(where: { candidate in
                guard let meta = candidate.metadata,
                      let postedBlobSHA = meta.fileInfo?.blobSHA,
                      !postedBlobSHA.isEmpty else {
                    return false
                }
                return postedBlobSHA == pendingBlobSHA
            }) {
                consumedIds.insert(shiftedMatch.id)
                return .redetected(pending: pending, posted: shiftedMatch)
            }

            // Tier 4: File-changed — same rule + file but different blob SHA means file was modified
            if let fileChangedMatch = candidates.first(where: { candidate in
                guard let meta = candidate.metadata,
                      let postedBlobSHA = meta.fileInfo?.blobSHA,
                      !postedBlobSHA.isEmpty else {
                    return false
                }
                return postedBlobSHA != pendingBlobSHA
            }) {
                consumedIds.insert(fileChangedMatch.id)
                return .new(pending: pending)
            }
        }

        // Fallback: candidates exist but no blob SHA available for comparison
        if let fallbackMatch = candidates.first(where: { !consumedIds.contains($0.id) }) {
            consumedIds.insert(fallbackMatch.id)
            let postedBody = fallbackMatch.bodyWithoutMetadata
            if pendingBody == postedBody {
                return .redetected(pending: pending, posted: fallbackMatch)
            } else {
                return .needsUpdate(pending: pending, posted: fallbackMatch)
            }
        }

        return nil
    }

    /// Try to match a pending violation against v0 (legacy, no metadata) posted comments.
    /// Legacy matches always produce `.needsUpdate` to upgrade the comment with v1 metadata.
    private static func matchV0(
        pending: PRComment,
        index: inout [String: [Int?: [GitHubReviewComment]]],
        consumedIds: inout Set<String>
    ) -> ReviewComment? {
        let key = pending.lineNumber
        guard var candidates = index[pending.filePath]?[key]?.filter({ !consumedIds.contains($0.id) }),
              !candidates.isEmpty else {
            return nil
        }

        if let matchIndex = candidates.firstIndex(where: { $0.body.contains(pending.ruleName) }) {
            let matched = candidates.remove(at: matchIndex)
            consumedIds.insert(matched.id)
            // v0 comments always need updating to embed v1 metadata
            return .needsUpdate(pending: pending, posted: matched)
        }

        return nil
    }
}
