import Foundation
import PRRadarModels

public struct RegexAnalysisService: Sendable {

    public init() {}

    /// Evaluate a regex pattern against classified diff lines.
    ///
    /// When `newCodeLinesOnly` is set on the rule, only `.new` and `.changedInMove`
    /// lines are checked. Otherwise all changed lines (new, removed, changedInMove)
    /// are checked.
    public func analyzeTask(
        _ task: RuleRequest,
        pattern: String,
        classifiedHunks: [ClassifiedHunk]
    ) -> RuleOutcome {
        let startTime = CFAbsoluteTimeGetCurrent()

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

        let linesToCheck: [ClassifiedDiffLine]
        if task.rule.newCodeLinesOnly {
            linesToCheck = classifiedHunks.flatMap { $0.lines.filter {
                $0.classification == .new || $0.classification == .changedInMove
            }}
        } else {
            linesToCheck = classifiedHunks.flatMap { $0.changedLines }
        }

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

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

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
