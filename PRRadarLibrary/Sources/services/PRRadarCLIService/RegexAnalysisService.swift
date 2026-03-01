import Foundation
import PRRadarModels

public struct RegexAnalysisService: Sendable {

    public init() {}

    /// Filter classified hunks to only include lines within a focus area's file and line range.
    public static func filterHunksForFocusArea(
        _ hunks: [ClassifiedHunk],
        focusArea: FocusArea
    ) -> [ClassifiedHunk] {
        hunks.compactMap { hunk in
            guard hunk.filePath == focusArea.filePath else { return nil }
            let filteredLines = hunk.lines.filter { line in
                guard let lineNum = line.newLineNumber ?? line.oldLineNumber else { return false }
                return lineNum >= focusArea.startLine && lineNum <= focusArea.endLine
            }
            guard !filteredLines.isEmpty else { return nil }
            return ClassifiedHunk(
                filePath: hunk.filePath,
                oldStart: hunk.oldStart,
                newStart: hunk.newStart,
                lines: filteredLines
            )
        }
    }

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
