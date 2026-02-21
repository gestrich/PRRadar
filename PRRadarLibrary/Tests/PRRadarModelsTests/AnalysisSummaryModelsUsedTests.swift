import Testing
@testable import PRRadarModels
@testable import PRReviewFeature

@Suite("PRReviewResult modelsUsed")
struct PRReviewResultModelsUsedTests {

    @Test("Returns distinct sorted model IDs from evaluations")
    func distinctSortedModels() {
        // Arrange
        let result = PRReviewResult(
            evaluations: [
                makeResult(taskId: "t1", modelUsed: "claude-sonnet-4-20250514"),
                makeResult(taskId: "t2", modelUsed: "claude-haiku-4-5-20251001"),
                makeResult(taskId: "t3", modelUsed: "claude-sonnet-4-20250514"),
            ],
            summary: makeSummary(totalTasks: 3, violationsFound: 1)
        )

        // Act
        let models = result.modelsUsed

        // Assert
        #expect(models == ["claude-haiku-4-5-20251001", "claude-sonnet-4-20250514"])
    }

    @Test("Returns empty array when no evaluations")
    func emptyEvaluations() {
        // Arrange
        let result = PRReviewResult(
            evaluations: [],
            summary: makeSummary(totalTasks: 0, violationsFound: 0)
        )

        // Act
        let models = result.modelsUsed

        // Assert
        #expect(models.isEmpty)
    }

    @Test("Returns single model when all evaluations use same model")
    func singleModel() {
        // Arrange
        let result = PRReviewResult(
            evaluations: [
                makeResult(taskId: "t1", modelUsed: "claude-sonnet-4-20250514"),
                makeResult(taskId: "t2", modelUsed: "claude-sonnet-4-20250514"),
            ],
            summary: makeSummary(totalTasks: 2, violationsFound: 0)
        )

        // Act
        let models = result.modelsUsed

        // Assert
        #expect(models == ["claude-sonnet-4-20250514"])
    }

    // MARK: - Helpers

    private func makeResult(taskId: String, modelUsed: String) -> RuleOutcome {
        .success(RuleResult(
            taskId: taskId,
            ruleName: "test-rule",
            filePath: "test.swift",
            modelUsed: modelUsed,
            durationMs: 1000,
            costUsd: 0.001,
            violatesRule: false,
            score: 1,
            comment: "OK",
            lineNumber: nil
        ))
    }

    private func makeSummary(totalTasks: Int, violationsFound: Int) -> PRReviewSummary {
        PRReviewSummary(
            prNumber: 1,
            evaluatedAt: "2025-01-01T00:00:00Z",
            totalTasks: totalTasks,
            violationsFound: violationsFound,
            totalCostUsd: 0.01,
            totalDurationMs: 3000
        )
    }
}
