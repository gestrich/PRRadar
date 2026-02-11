import Foundation
import PRRadarConfigService
import PRRadarModels

/// Pure transformation service for converting evaluation results into PRComment instances.
public struct ViolationService: Sendable {
    public init() {}

    /// Filter evaluation results by violation status and score, converting to PRComment instances.
    public static func filterByScore(
        results: [RuleEvaluationResult],
        tasks: [EvaluationTaskOutput],
        minScore: Int
    ) -> [PRComment] {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
        var comments: [PRComment] = []

        for result in results {
            guard result.evaluation.violatesRule else { continue }
            guard result.evaluation.score >= minScore else { continue }
            comments.append(PRComment.from(evaluation: result, task: taskMap[result.taskId]))
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
        var taskMetadata: [String: EvaluationTaskOutput] = [:]
        if let taskFiles = try? fm.contentsOfDirectory(atPath: tasksDir) {
            for file in taskFiles where file.hasPrefix(DataPathsService.dataFilePrefix) {
                let path = "\(tasksDir)/\(file)"
                guard let data = fm.contents(atPath: path),
                      let task = try? JSONDecoder().decode(EvaluationTaskOutput.self, from: data) else { continue }
                taskMetadata[task.taskId] = task
            }
        }

        guard let evalFiles = try? fm.contentsOfDirectory(atPath: evaluationsDir) else { return comments }

        for file in evalFiles where file.hasPrefix(DataPathsService.dataFilePrefix) {
            let path = "\(evaluationsDir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let result = try? JSONDecoder().decode(RuleEvaluationResult.self, from: data) else { continue }

            guard result.evaluation.violatesRule else { continue }
            guard result.evaluation.score >= minScore else { continue }

            comments.append(PRComment.from(evaluation: result, task: taskMetadata[result.taskId]))
        }

        return comments
    }

    /// Match pending violations against posted GitHub review comments to produce a unified list.
    ///
    /// Each posted comment is consumed at most once (first-match wins). Unmatched pending
    /// comments become `.new`, unmatched posted comments become `.postedOnly`, and matches
    /// become `.redetected`.
    ///
    /// Matching uses a two-pass strategy per pending comment:
    /// 1. **Exact match:** same file, same line, body contains rule name
    /// 2. **Fuzzy fallback:** same file, any line, body contains rule name
    ///    This handles line-shift scenarios where GitHub updates posted comment line numbers
    ///    after new commits are pushed to the branch, causing them to drift from the AI
    ///    evaluator's reported line numbers.
    public static func reconcile(
        pending: [PRComment],
        posted: [GitHubReviewComment]
    ) -> [ReviewComment] {
        // Index posted comments by (filePath, lineNumber) for efficient lookup.
        // Multiple posted comments can exist at the same (file, line).
        var postedByFileAndLine: [String: [Int?: [GitHubReviewComment]]] = [:]
        for comment in posted {
            postedByFileAndLine[comment.path, default: [:]][comment.line, default: []].append(comment)
        }

        var results: [ReviewComment] = []

        for p in pending {
            // Pass 1: exact (file, line) match
            let key = p.lineNumber
            if var candidates = postedByFileAndLine[p.filePath]?[key] {
                if let matchIndex = candidates.firstIndex(where: { $0.body.contains(p.ruleName) }) {
                    let matched = candidates.remove(at: matchIndex)
                    postedByFileAndLine[p.filePath]![key] = candidates
                    if candidates.isEmpty {
                        postedByFileAndLine[p.filePath]!.removeValue(forKey: key)
                    }
                    results.append(ReviewComment(pending: p, posted: matched))
                    continue
                }
            }

            // Pass 2: same file, different line — handles line drift from branch updates.
            // Only applies when the pending comment is line-specific (non-nil lineNumber).
            // File-level comments (nil line) must match exactly in Pass 1.
            if p.lineNumber != nil, let byLine = postedByFileAndLine[p.filePath] {
                var matched: GitHubReviewComment?
                for (lineKey, candidates) in byLine where lineKey != nil {
                    if let matchIndex = candidates.firstIndex(where: { $0.body.contains(p.ruleName) }) {
                        matched = candidates[matchIndex]
                        var remaining = candidates
                        remaining.remove(at: matchIndex)
                        postedByFileAndLine[p.filePath]![lineKey] = remaining
                        if remaining.isEmpty {
                            postedByFileAndLine[p.filePath]!.removeValue(forKey: lineKey)
                        }
                        break
                    }
                }
                if let matched {
                    results.append(ReviewComment(pending: p, posted: matched))
                    continue
                }
            }

            results.append(ReviewComment(pending: p, posted: nil))
        }

        // Remaining unmatched posted comments
        for (_, byLine) in postedByFileAndLine {
            for (_, comments) in byLine {
                for comment in comments {
                    results.append(ReviewComment(pending: nil, posted: comment))
                }
            }
        }

        return results
    }
}
