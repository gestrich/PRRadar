import Testing
@testable import PRRadarModels

@Suite("PRComment modelUsed threading")
struct PRCommentModelUsedTests {

    @Test("from() copies modelUsed from EvaluationSuccess")
    func fromCopiesModelUsed() {
        // Arrange
        let evaluation = EvaluationSuccess(
            taskId: "task-1",
            ruleName: "test-rule",
            filePath: "src/app.swift",
            evaluation: RuleEvaluation(
                violatesRule: true,
                score: 7,
                comment: "Issue found",
                filePath: "src/app.swift",
                lineNumber: 10
            ),
            modelUsed: "claude-sonnet-4-20250514",
            durationMs: 1000,
            costUsd: 0.003
        )

        // Act
        let comment = PRComment.from(evaluation: evaluation, task: nil)

        // Assert
        #expect(comment.modelUsed == "claude-sonnet-4-20250514")
    }

    @Test("from() copies costUsd alongside modelUsed")
    func fromCopiesCostAndModel() {
        // Arrange
        let evaluation = EvaluationSuccess(
            taskId: "task-2",
            ruleName: "naming-rule",
            filePath: "src/utils.swift",
            evaluation: RuleEvaluation(
                violatesRule: true,
                score: 5,
                comment: "Naming violation",
                filePath: "src/utils.swift",
                lineNumber: 42
            ),
            modelUsed: "claude-haiku-4-5-20251001",
            durationMs: 500,
            costUsd: 0.001
        )

        // Act
        let comment = PRComment.from(evaluation: evaluation, task: nil)

        // Assert
        #expect(comment.costUsd == 0.001)
        #expect(comment.modelUsed == "claude-haiku-4-5-20251001")
    }
}
