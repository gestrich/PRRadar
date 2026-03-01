import Testing
@testable import PRRadarModels

@Suite("PRComment analysisMethod threading")
struct PRCommentAnalysisMethodTests {

    @Test("from(violation:) copies analysisMethod from RuleResult")
    func fromCopiesAnalysisMethod() {
        // Arrange
        let violation = Violation(score: 7, comment: "Issue found", filePath: "src/app.swift", lineNumber: 10)
        let result = RuleResult(
            taskId: "task-1",
            ruleName: "test-rule",
            filePath: "src/app.swift",
            analysisMethod: .ai(model: "claude-sonnet-4-20250514", costUsd: 0.003),
            durationMs: 1000,
            violations: [violation]
        )

        // Act
        let comment = PRComment.from(violation: violation, result: result, task: nil, index: 0)

        // Assert
        #expect(comment.analysisMethod == .ai(model: "claude-sonnet-4-20250514", costUsd: 0.003))
    }

    @Test("from(violation:) carries costUsd through analysisMethod")
    func fromCarriesCostThroughAnalysisMethod() {
        // Arrange
        let violation = Violation(score: 5, comment: "Naming violation", filePath: "src/utils.swift", lineNumber: 42)
        let result = RuleResult(
            taskId: "task-2",
            ruleName: "naming-rule",
            filePath: "src/utils.swift",
            analysisMethod: .ai(model: "claude-haiku-4-5-20251001", costUsd: 0.001),
            durationMs: 500,
            violations: [violation]
        )

        // Act
        let comment = PRComment.from(violation: violation, result: result, task: nil, index: 0)

        // Assert
        #expect(comment.costUsd == 0.001)
        #expect(comment.analysisMethod == .ai(model: "claude-haiku-4-5-20251001", costUsd: 0.001))
    }
}
