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
    ) -> (outcome: RuleOutcome, output: EvaluationOutput) {
        let startDate = Date()
        let startTime = startDate.timeIntervalSinceReferenceDate
        let startedAt = ISO8601DateFormatter().string(from: startDate)
        var entries: [OutputEntry] = []

        entries.append(OutputEntry(type: .text, content: pattern, label: "Regex pattern", timestamp: startDate))

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        } catch {
            let errorMessage = "Invalid regex pattern '\(pattern)': \(error.localizedDescription)"
            entries.append(OutputEntry(type: .error, content: errorMessage, timestamp: Date()))
            let durationMs = Int((Date().timeIntervalSinceReferenceDate - startTime) * 1000)
            let output = EvaluationOutput(
                identifier: task.taskId,
                filePath: task.focusArea.filePath,
                rule: task.rule,
                source: .regex(pattern: pattern),
                startedAt: startedAt,
                durationMs: durationMs,
                costUsd: 0,
                entries: entries
            )
            let outcome = RuleOutcome.error(RuleError(
                taskId: task.taskId,
                ruleName: task.rule.name,
                filePath: task.focusArea.filePath,
                errorMessage: errorMessage,
                analysisMethod: .regex(pattern: pattern)
            ))
            return (outcome, output)
        }

        let linesToCheck = hunks.flatMap {
            $0.relevantLines(newCodeLinesOnly: task.rule.newCodeLinesOnly)
        }.filter { !$0.isSurroundingWhitespaceOnlyChange }

        let comment = task.rule.violationMessage ?? task.rule.description

        var matchedLines: [String] = []
        var violations: [Violation] = []
        for line in linesToCheck {
            let text = line.content
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, range: range) != nil {
                let lineNum = line.newLineNumber ?? line.oldLineNumber
                matchedLines.append("L\(lineNum.map { String($0) } ?? "?"): \(text)")
                violations.append(Violation(
                    score: 5,
                    comment: comment,
                    filePath: line.filePath,
                    lineNumber: lineNum
                ))
            }
        }

        if matchedLines.isEmpty {
            entries.append(OutputEntry(type: .text, content: "No matches found", label: "Matched lines", timestamp: Date()))
        } else {
            entries.append(OutputEntry(type: .text, content: matchedLines.joined(separator: "\n"), label: "Matched lines", timestamp: Date()))
        }

        let violationSummary = violations.isEmpty ? "No violations" : "\(violations.count) violation(s) found"
        entries.append(OutputEntry(type: .result, content: violationSummary, timestamp: Date()))

        let durationMs = Int((Date().timeIntervalSinceReferenceDate - startTime) * 1000)

        let result = RuleResult(
            taskId: task.taskId,
            ruleName: task.rule.name,
            filePath: task.focusArea.filePath,
            analysisMethod: .regex(pattern: pattern),
            durationMs: durationMs,
            violations: violations
        )

        let output = EvaluationOutput(
            identifier: task.taskId,
            filePath: task.focusArea.filePath,
            rule: task.rule,
            source: .regex(pattern: pattern),
            startedAt: startedAt,
            durationMs: durationMs,
            costUsd: 0,
            entries: entries
        )

        return (.success(result), output)
    }
}
