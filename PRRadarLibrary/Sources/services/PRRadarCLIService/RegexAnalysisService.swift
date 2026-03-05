import Foundation
import PRRadarModels

public struct RegexAnalysisService: Sendable {

    public init() {}

    /// Evaluate a regex pattern against classified diff lines.
    ///
    /// When `newCodeLinesOnly` is set, only lines with `changeKind == .added` are checked.
    /// Otherwise all changed lines (`changeKind != .unchanged`) are checked.
    public func analyzeTask(
        _ task: RuleRequest,
        pattern: String,
        hunks: [PRHunk]
    ) -> RuleOutcome {
        let startTime = Date().timeIntervalSinceReferenceDate

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        } catch {
            return .error(RuleError(
                taskId: task.taskId,
                ruleName: task.rule.name,
                filePath: task.focusArea.filePath,
                errorMessage: "Invalid regex pattern '\(pattern)': \(error.localizedDescription)",
                analysisMethod: .regex(pattern: pattern)
            ))
        }

        let linesToCheck = hunks.flatMap {
            $0.relevantLines(newCodeLinesOnly: task.rule.newCodeLinesOnly)
        }.filter { !$0.isSurroundingWhitespaceOnlyChange }

        let comment = task.rule.violationMessage ?? task.rule.description

        var violations: [Violation] = []
        for line in linesToCheck {
            let text = line.content
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, range: range) != nil {
                violations.append(Violation(
                    score: 5,
                    comment: comment,
                    filePath: line.filePath,
                    lineNumber: line.newLineNumber ?? line.oldLineNumber
                ))
            }
        }

        let durationMs = Int((Date().timeIntervalSinceReferenceDate - startTime) * 1000)

        let result = RuleResult(
            taskId: task.taskId,
            ruleName: task.rule.name,
            filePath: task.focusArea.filePath,
            analysisMethod: .regex(pattern: pattern),
            durationMs: durationMs,
            violations: violations
        )

        return .success(result)
    }
}
