import Foundation

/// Structured PR comment model holding all component fields.
///
/// This is the single source of truth for comment data. Rendering for
/// GitHub markdown vs SwiftUI consumes these fields differently.
public struct PRComment: Sendable, Identifiable {
    public let id: String
    public let ruleName: String
    public let score: Int
    public let comment: String
    public let filePath: String
    public let lineNumber: Int?
    public let documentationLink: String?
    public let relevantClaudeSkill: String?
    public let ruleUrl: String?
    public let costUsd: Double?
    public let modelUsed: String?

    public init(
        id: String,
        ruleName: String,
        score: Int,
        comment: String,
        filePath: String,
        lineNumber: Int?,
        documentationLink: String? = nil,
        relevantClaudeSkill: String? = nil,
        ruleUrl: String? = nil,
        costUsd: Double? = nil,
        modelUsed: String? = nil
    ) {
        self.id = id
        self.ruleName = ruleName
        self.score = score
        self.comment = comment
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.documentationLink = documentationLink
        self.relevantClaudeSkill = relevantClaudeSkill
        self.ruleUrl = ruleUrl
        self.costUsd = costUsd
        self.modelUsed = modelUsed
    }

    /// Create from an evaluation result and its associated task metadata.
    public static func from(
        evaluation: RuleEvaluationResult,
        task: AnalysisTaskOutput?
    ) -> PRComment {
        PRComment(
            id: evaluation.taskId,
            ruleName: evaluation.ruleName,
            score: evaluation.evaluation.score,
            comment: evaluation.evaluation.comment,
            filePath: evaluation.evaluation.filePath.isEmpty
                ? evaluation.filePath
                : evaluation.evaluation.filePath,
            lineNumber: evaluation.evaluation.lineNumber,
            documentationLink: task?.rule.documentationLink,
            relevantClaudeSkill: task?.rule.relevantClaudeSkill,
            ruleUrl: task?.rule.ruleUrl,
            costUsd: evaluation.costUsd,
            modelUsed: evaluation.modelUsed
        )
    }

    /// Render the comment as GitHub-flavored markdown for posting as a PR comment.
    public func toGitHubMarkdown() -> String {
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

        var metaParts: [String] = []
        if let cost = costUsd {
            metaParts.append(String(format: "cost $%.4f", cost))
        }
        if let model = modelUsed {
            metaParts.append(displayName(forModelId: model))
        }
        let metaStr = metaParts.isEmpty ? "" : " (\(metaParts.joined(separator: " · ")))"
        lines.append("")
        lines.append("*Assisted by [PR Radar](https://github.com/gestrich/PRRadar)\(metaStr)*")

        return lines.joined(separator: "\n")
    }
}
