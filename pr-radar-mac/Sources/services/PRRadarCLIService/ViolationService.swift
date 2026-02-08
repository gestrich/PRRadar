import Foundation
import PRRadarModels

/// Represents a violation ready for posting as a GitHub comment.
public struct CommentableViolation: Sendable {
    public let taskId: String
    public let ruleName: String
    public let filePath: String
    public let lineNumber: Int?
    public let score: Int
    public let comment: String
    public let documentationLink: String?
    public let relevantClaudeSkill: String?
    public let costUsd: Double?
    public let diffContext: String?
    public let ruleUrl: String?

    public init(
        taskId: String,
        ruleName: String,
        filePath: String,
        lineNumber: Int?,
        score: Int,
        comment: String,
        documentationLink: String? = nil,
        relevantClaudeSkill: String? = nil,
        costUsd: Double? = nil,
        diffContext: String? = nil,
        ruleUrl: String? = nil
    ) {
        self.taskId = taskId
        self.ruleName = ruleName
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.score = score
        self.comment = comment
        self.documentationLink = documentationLink
        self.relevantClaudeSkill = relevantClaudeSkill
        self.costUsd = costUsd
        self.diffContext = diffContext
        self.ruleUrl = ruleUrl
    }

    /// Compose the final GitHub comment body with rule header, comment, and metadata.
    public func composeComment() -> String {
        let ruleHeader: String
        if let ruleUrl {
            ruleHeader = "**[\(ruleName)](\(ruleUrl))**"
        } else {
            ruleHeader = "**\(ruleName)**"
        }

        var lines = [ruleHeader, "", comment]

        if let relevantClaudeSkill {
            lines.append("")
            lines.append("Related Claude Skill: `/\(relevantClaudeSkill)`")
        }

        if let documentationLink {
            lines.append("")
            lines.append("Related Documentation: [Docs](\(documentationLink))")
        }

        let costStr = costUsd.map { String(format: " (cost $%.4f)", $0) } ?? ""
        lines.append("")
        lines.append("*Assisted by [PR Radar](https://github.com/gestrich/PRRadar)\(costStr)*")

        return lines.joined(separator: "\n")
    }
}

/// Pure transformation service for converting evaluation results into commentable violations.
public struct ViolationService: Sendable {
    public init() {}

    /// Create a commentable violation from an evaluation result and task.
    public static func createViolation(
        result: RuleEvaluationResult,
        task: EvaluationTaskOutput
    ) -> CommentableViolation {
        let diffContext = task.focusArea.getContextAroundLine(
            result.evaluation.lineNumber,
            contextLines: 3
        )

        return CommentableViolation(
            taskId: result.taskId,
            ruleName: result.ruleName,
            filePath: result.filePath,
            lineNumber: result.evaluation.lineNumber,
            score: result.evaluation.score,
            comment: result.evaluation.comment,
            documentationLink: task.rule.documentationLink,
            costUsd: result.costUsd,
            diffContext: diffContext
        )
    }

    /// Filter evaluation results by violation status and score, converting to commentable violations.
    public static func filterByScore(
        results: [RuleEvaluationResult],
        tasks: [EvaluationTaskOutput],
        minScore: Int
    ) -> [CommentableViolation] {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
        var violations: [CommentableViolation] = []

        for result in results {
            guard result.evaluation.violatesRule else { continue }
            guard result.evaluation.score >= minScore else { continue }
            guard let task = taskMap[result.taskId] else { continue }
            violations.append(createViolation(result: result, task: task))
        }

        return violations
    }

    /// Load violations from evaluation result files on disk.
    public static func loadViolations(
        evaluationsDir: String,
        tasksDir: String,
        minScore: Int
    ) -> [CommentableViolation] {
        let fm = FileManager.default
        var violations: [CommentableViolation] = []

        // Load task metadata
        var taskMetadata: [String: EvaluationTaskOutput] = [:]
        if let taskFiles = try? fm.contentsOfDirectory(atPath: tasksDir) {
            for file in taskFiles where file.hasSuffix(".json") {
                let path = "\(tasksDir)/\(file)"
                guard let data = fm.contents(atPath: path),
                      let task = try? JSONDecoder().decode(EvaluationTaskOutput.self, from: data) else { continue }
                taskMetadata[task.taskId] = task
            }
        }

        guard let evalFiles = try? fm.contentsOfDirectory(atPath: evaluationsDir) else { return violations }

        for file in evalFiles where file.hasSuffix(".json") && file != "summary.json" {
            let path = "\(evaluationsDir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let result = try? JSONDecoder().decode(RuleEvaluationResult.self, from: data) else { continue }

            guard result.evaluation.violatesRule else { continue }
            guard result.evaluation.score >= minScore else { continue }

            let filePath = result.filePath.isEmpty ? result.evaluation.filePath : result.filePath

            let documentationLink: String?
            if let task = taskMetadata[result.taskId] {
                documentationLink = task.rule.documentationLink
            } else {
                documentationLink = nil
            }

            violations.append(CommentableViolation(
                taskId: result.taskId,
                ruleName: result.ruleName,
                filePath: filePath,
                lineNumber: result.evaluation.lineNumber,
                score: result.evaluation.score,
                comment: result.evaluation.comment,
                documentationLink: documentationLink,
                costUsd: result.costUsd
            ))
        }

        return violations
    }
}
