import Testing
@testable import PRRadarModels

@Suite("PRComment modelUsed threading")
struct PRCommentModelUsedTests {

    @Test("from(violation:) copies modelUsed from RuleResult")
    func fromCopiesModelUsed() {
        // Arrange
        let violation = Violation(score: 7, comment: "Issue found", filePath: "src/app.swift", lineNumber: 10)
        let result = RuleResult(
            taskId: "task-1",
            ruleName: "test-rule",
            filePath: "src/app.swift",
            modelUsed: "claude-sonnet-4-20250514",
            durationMs: 1000,
            costUsd: 0.003,
            violations: [violation]
        )

        // Act
        let comment = PRComment.from(violation: violation, result: result, task: nil, index: 0)

        // Assert
        #expect(comment.modelUsed == "claude-sonnet-4-20250514")
    }

    @Test("from(violation:) copies costUsd alongside modelUsed")
    func fromCopiesCostAndModel() {
        // Arrange
        let violation = Violation(score: 5, comment: "Naming violation", filePath: "src/utils.swift", lineNumber: 42)
        let result = RuleResult(
            taskId: "task-2",
            ruleName: "naming-rule",
            filePath: "src/utils.swift",
            modelUsed: "claude-haiku-4-5-20251001",
            durationMs: 500,
            costUsd: 0.001,
            violations: [violation]
        )

        // Act
        let comment = PRComment.from(violation: violation, result: result, task: nil, index: 0)

        // Assert
        #expect(comment.costUsd == 0.001)
        #expect(comment.modelUsed == "claude-haiku-4-5-20251001")
    }
}
