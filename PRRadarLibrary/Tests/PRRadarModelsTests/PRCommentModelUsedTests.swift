import Testing
@testable import PRRadarModels

@Suite("PRComment modelUsed threading")
struct PRCommentModelUsedTests {

    @Test("from() copies modelUsed from RuleResult")
    func fromCopiesModelUsed() {
        // Arrange
        let result = RuleResult(
            taskId: "task-1",
            ruleName: "test-rule",
            filePath: "src/app.swift",
            modelUsed: "claude-sonnet-4-20250514",
            durationMs: 1000,
            costUsd: 0.003,
            violatesRule: true,
            score: 7,
            comment: "Issue found",
            lineNumber: 10
        )

        // Act
        let comment = PRComment.from(result: result, task: nil)

        // Assert
        #expect(comment.modelUsed == "claude-sonnet-4-20250514")
    }

    @Test("from() copies costUsd alongside modelUsed")
    func fromCopiesCostAndModel() {
        // Arrange
        let result = RuleResult(
            taskId: "task-2",
            ruleName: "naming-rule",
            filePath: "src/utils.swift",
            modelUsed: "claude-haiku-4-5-20251001",
            durationMs: 500,
            costUsd: 0.001,
            violatesRule: true,
            score: 5,
            comment: "Naming violation",
            lineNumber: 42
        )

        // Act
        let comment = PRComment.from(result: result, task: nil)

        // Assert
        #expect(comment.costUsd == 0.001)
        #expect(comment.modelUsed == "claude-haiku-4-5-20251001")
    }
}
