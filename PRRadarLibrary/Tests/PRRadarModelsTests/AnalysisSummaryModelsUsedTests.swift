import Testing
@testable import PRRadarModels

@Suite("AnalysisSummary modelsUsed")
struct AnalysisSummaryModelsUsedTests {

    @Test("Returns distinct sorted model IDs from results")
    func distinctSortedModels() {
        // Arrange
        let summary = AnalysisSummary(
            prNumber: 1,
            evaluatedAt: "2025-01-01T00:00:00Z",
            totalTasks: 3,
            violationsFound: 1,
            totalCostUsd: 0.01,
            totalDurationMs: 3000,
            results: [
                makeResult(taskId: "t1", modelUsed: "claude-sonnet-4-20250514"),
                makeResult(taskId: "t2", modelUsed: "claude-haiku-4-5-20251001"),
                makeResult(taskId: "t3", modelUsed: "claude-sonnet-4-20250514"),
            ]
        )

        // Act
        let models = summary.modelsUsed

        // Assert
        #expect(models == ["claude-haiku-4-5-20251001", "claude-sonnet-4-20250514"])
    }

    @Test("Returns empty array when no results")
    func emptyResults() {
        // Arrange
        let summary = AnalysisSummary(
            prNumber: 1,
            evaluatedAt: "2025-01-01T00:00:00Z",
            totalTasks: 0,
            violationsFound: 0,
            totalCostUsd: 0.0,
            totalDurationMs: 0,
            results: []
        )

        // Act
        let models = summary.modelsUsed

        // Assert
        #expect(models.isEmpty)
    }

    @Test("Returns single model when all results use same model")
    func singleModel() {
        // Arrange
        let summary = AnalysisSummary(
            prNumber: 1,
            evaluatedAt: "2025-01-01T00:00:00Z",
            totalTasks: 2,
            violationsFound: 0,
            totalCostUsd: 0.005,
            totalDurationMs: 2000,
            results: [
                makeResult(taskId: "t1", modelUsed: "claude-sonnet-4-20250514"),
                makeResult(taskId: "t2", modelUsed: "claude-sonnet-4-20250514"),
            ]
        )

        // Act
        let models = summary.modelsUsed

        // Assert
        #expect(models == ["claude-sonnet-4-20250514"])
    }

    // MARK: - Helpers

    private func makeResult(taskId: String, modelUsed: String) -> RuleEvaluationResult {
        RuleEvaluationResult(
            taskId: taskId,
            ruleName: "test-rule",
            ruleFilePath: "/rules/test.md",
            filePath: "test.swift",
            evaluation: RuleEvaluation(
                violatesRule: false,
                score: 1,
                comment: "OK",
                filePath: "test.swift",
                lineNumber: nil
            ),
            modelUsed: modelUsed,
            durationMs: 1000,
            costUsd: 0.001
        )
    }
}
