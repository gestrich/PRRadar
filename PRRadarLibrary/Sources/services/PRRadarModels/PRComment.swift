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
    public let analysisMethod: AnalysisMethod?
    public let ruleHash: String
    public let fileBlobSHA: String?
    public let suppressionRole: SuppressionRole?
    public let maxCommentsPerFile: Int?

    public var costUsd: Double? { analysisMethod?.costUsd }

    public var effectiveBlobSHA: String? {
        guard let sha = fileBlobSHA, !sha.isEmpty else { return nil }
        return sha
    }

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
        analysisMethod: AnalysisMethod? = nil,
        ruleHash: String,
        fileBlobSHA: String? = nil,
        suppressionRole: SuppressionRole? = nil,
        maxCommentsPerFile: Int? = nil
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
        self.analysisMethod = analysisMethod
        self.ruleHash = ruleHash
        self.fileBlobSHA = fileBlobSHA
        self.suppressionRole = suppressionRole
        self.maxCommentsPerFile = maxCommentsPerFile
    }

    /// Creates a comment from an individual violation and its parent result metadata.
    public static func from(
        violation: Violation,
        result: RuleResult,
        task: RuleRequest,
        index: Int
    ) -> PRComment {
        PRComment(
            id: "\(result.taskId)_\(index)",
            ruleName: result.ruleName,
            score: violation.score,
            comment: violation.comment,
            filePath: violation.filePath,
            lineNumber: violation.lineNumber,
            documentationLink: task.rule.documentationLink,
            relevantClaudeSkill: task.rule.relevantClaudeSkill,
            ruleUrl: task.rule.ruleUrl,
            analysisMethod: result.analysisMethod,
            ruleHash: task.ruleBlobHash,
            fileBlobSHA: task.gitBlobHash,
            maxCommentsPerFile: task.rule.maxCommentsPerFile
        )
    }

    public func withSuppression(role: SuppressionRole) -> PRComment {
        PRComment(
            id: id,
            ruleName: ruleName,
            score: score,
            comment: comment,
            filePath: filePath,
            lineNumber: lineNumber,
            documentationLink: documentationLink,
            relevantClaudeSkill: relevantClaudeSkill,
            ruleUrl: ruleUrl,
            analysisMethod: analysisMethod,
            ruleHash: ruleHash,
            fileBlobSHA: fileBlobSHA,
            suppressionRole: role,
            maxCommentsPerFile: maxCommentsPerFile
        )
    }

    /// Build metadata for this comment at posting time.
    public func buildMetadata(prHeadSHA: String) -> CommentMetadata {
        CommentMetadata(
            rule: .init(id: ruleName, hash: ruleHash),
            fileInfo: .init(path: filePath, line: lineNumber, blobSHA: fileBlobSHA),
            prHeadSHA: prHeadSHA,
            suppressionRole: suppressionRole
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
        if let method = analysisMethod {
            if method.costUsd > 0 {
                metaParts.append(String(format: "cost $%.4f", method.costUsd))
            }
            metaParts.append(method.displayName)
        }
        let metaStr = metaParts.isEmpty ? "" : " (\(metaParts.joined(separator: " · ")))"
        lines.append("")
        lines.append("*Assisted by [PR Radar](https://github.com/gestrich/PRRadar)\(metaStr)*")

        return lines.joined(separator: "\n")
    }
}
