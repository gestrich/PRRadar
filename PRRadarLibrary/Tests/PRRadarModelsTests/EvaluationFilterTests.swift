import Foundation
import Testing
@testable import PRRadarModels

@Suite("EvaluationFilter")
struct EvaluationFilterTests {

    // MARK: - Helpers

    private func makeTask(
        ruleName: String = "error-handling",
        filePath: String = "src/handler.py",
        focusId: String = "method-handler_py-process-10-25"
    ) -> EvaluationTaskOutput {
        EvaluationTaskOutput(
            taskId: "\(ruleName)_\(focusId)",
            rule: TaskRule(
                name: ruleName,
                description: "Test rule",
                category: "test",
                content: "Rule content"
            ),
            focusArea: FocusArea(
                focusId: focusId,
                filePath: filePath,
                startLine: 10,
                endLine: 25,
                description: "focus area",
                hunkIndex: 0,
                hunkContent: "@@ content"
            ),
            gitBlobHash: "abc123"
        )
    }

    // MARK: - isEmpty

    @Test("isEmpty returns true when all fields are nil")
    func isEmptyAllNil() {
        // Arrange
        let filter = EvaluationFilter()

        // Assert
        #expect(filter.isEmpty)
    }

    @Test("isEmpty returns false when filePath is set")
    func isEmptyWithFilePath() {
        // Arrange
        let filter = EvaluationFilter(filePath: "src/handler.py")

        // Assert
        #expect(!filter.isEmpty)
    }

    @Test("isEmpty returns false when focusAreaId is set")
    func isEmptyWithFocusAreaId() {
        // Arrange
        let filter = EvaluationFilter(focusAreaId: "focus-1")

        // Assert
        #expect(!filter.isEmpty)
    }

    @Test("isEmpty returns false when ruleNames is set")
    func isEmptyWithRuleNames() {
        // Arrange
        let filter = EvaluationFilter(ruleNames: ["error-handling"])

        // Assert
        #expect(!filter.isEmpty)
    }

    // MARK: - matches: no filter (all nil)

    @Test("Empty filter matches any task")
    func emptyFilterMatchesAll() {
        // Arrange
        let filter = EvaluationFilter()
        let task = makeTask()

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(result)
    }

    // MARK: - matches: filePath filter

    @Test("Filter matches task with matching file path")
    func filePathMatch() {
        // Arrange
        let filter = EvaluationFilter(filePath: "src/handler.py")
        let task = makeTask(filePath: "src/handler.py")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(result)
    }

    @Test("Filter rejects task with different file path")
    func filePathMismatch() {
        // Arrange
        let filter = EvaluationFilter(filePath: "src/other.py")
        let task = makeTask(filePath: "src/handler.py")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(!result)
    }

    @Test("File path filter requires exact match")
    func filePathExactMatch() {
        // Arrange
        let filter = EvaluationFilter(filePath: "src/handler")
        let task = makeTask(filePath: "src/handler.py")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(!result)
    }

    // MARK: - matches: focusAreaId filter

    @Test("Filter matches task with matching focus area ID")
    func focusAreaIdMatch() {
        // Arrange
        let filter = EvaluationFilter(focusAreaId: "method-handler_py-process-10-25")
        let task = makeTask(focusId: "method-handler_py-process-10-25")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(result)
    }

    @Test("Filter rejects task with different focus area ID")
    func focusAreaIdMismatch() {
        // Arrange
        let filter = EvaluationFilter(focusAreaId: "method-other-1-5")
        let task = makeTask(focusId: "method-handler_py-process-10-25")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(!result)
    }

    // MARK: - matches: ruleNames filter

    @Test("Filter matches task when rule name is in the list")
    func ruleNameMatch() {
        // Arrange
        let filter = EvaluationFilter(ruleNames: ["error-handling"])
        let task = makeTask(ruleName: "error-handling")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(result)
    }

    @Test("Filter matches task when rule name is one of multiple in the list")
    func ruleNameMatchMultiple() {
        // Arrange
        let filter = EvaluationFilter(ruleNames: ["naming-conventions", "error-handling", "logging"])
        let task = makeTask(ruleName: "error-handling")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(result)
    }

    @Test("Filter rejects task when rule name is not in the list")
    func ruleNameMismatch() {
        // Arrange
        let filter = EvaluationFilter(ruleNames: ["naming-conventions", "logging"])
        let task = makeTask(ruleName: "error-handling")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(!result)
    }

    @Test("Empty ruleNames array matches no tasks")
    func emptyRuleNamesArray() {
        // Arrange
        let filter = EvaluationFilter(ruleNames: [])
        let task = makeTask(ruleName: "error-handling")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(!result)
    }

    // MARK: - matches: combined filters (AND logic)

    @Test("Filter with filePath AND ruleNames matches task meeting both criteria")
    func combinedFilePathAndRuleName() {
        // Arrange
        let filter = EvaluationFilter(filePath: "src/handler.py", ruleNames: ["error-handling"])
        let task = makeTask(ruleName: "error-handling", filePath: "src/handler.py")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(result)
    }

    @Test("Filter with filePath AND ruleNames rejects task matching only filePath")
    func combinedFilterRejectsPartialFilePathMatch() {
        // Arrange
        let filter = EvaluationFilter(filePath: "src/handler.py", ruleNames: ["naming-conventions"])
        let task = makeTask(ruleName: "error-handling", filePath: "src/handler.py")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(!result)
    }

    @Test("Filter with filePath AND ruleNames rejects task matching only ruleNames")
    func combinedFilterRejectsPartialRuleNameMatch() {
        // Arrange
        let filter = EvaluationFilter(filePath: "src/other.py", ruleNames: ["error-handling"])
        let task = makeTask(ruleName: "error-handling", filePath: "src/handler.py")

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(!result)
    }

    @Test("Filter with all three criteria matches task meeting all")
    func allThreeCriteriaMatch() {
        // Arrange
        let filter = EvaluationFilter(
            filePath: "src/handler.py",
            focusAreaId: "method-handler_py-process-10-25",
            ruleNames: ["error-handling"]
        )
        let task = makeTask(
            ruleName: "error-handling",
            filePath: "src/handler.py",
            focusId: "method-handler_py-process-10-25"
        )

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(result)
    }

    @Test("Filter with all three criteria rejects task failing one criterion")
    func allThreeCriteriaOneFails() {
        // Arrange
        let filter = EvaluationFilter(
            filePath: "src/handler.py",
            focusAreaId: "method-handler_py-process-10-25",
            ruleNames: ["naming-conventions"]
        )
        let task = makeTask(
            ruleName: "error-handling",
            filePath: "src/handler.py",
            focusId: "method-handler_py-process-10-25"
        )

        // Act
        let result = filter.matches(task)

        // Assert
        #expect(!result)
    }

    // MARK: - matches: filtering a task list

    @Test("Filter by file path selects only tasks for that file")
    func filterTaskListByFile() {
        // Arrange
        let filter = EvaluationFilter(filePath: "src/handler.py")
        let tasks = [
            makeTask(ruleName: "rule-a", filePath: "src/handler.py", focusId: "f1"),
            makeTask(ruleName: "rule-b", filePath: "src/other.py", focusId: "f2"),
            makeTask(ruleName: "rule-c", filePath: "src/handler.py", focusId: "f3"),
        ]

        // Act
        let filtered = tasks.filter { filter.matches($0) }

        // Assert
        #expect(filtered.count == 2)
        #expect(filtered.map(\.rule.name) == ["rule-a", "rule-c"])
    }

    @Test("Filter by rule name selects only tasks for those rules")
    func filterTaskListByRuleNames() {
        // Arrange
        let filter = EvaluationFilter(ruleNames: ["error-handling", "logging"])
        let tasks = [
            makeTask(ruleName: "error-handling", focusId: "f1"),
            makeTask(ruleName: "naming-conventions", focusId: "f2"),
            makeTask(ruleName: "logging", focusId: "f3"),
            makeTask(ruleName: "security", focusId: "f4"),
        ]

        // Act
        let filtered = tasks.filter { filter.matches($0) }

        // Assert
        #expect(filtered.count == 2)
        #expect(filtered.map(\.rule.name) == ["error-handling", "logging"])
    }

    @Test("Combined filter narrows task list by both file and rule")
    func filterTaskListCombined() {
        // Arrange
        let filter = EvaluationFilter(filePath: "src/handler.py", ruleNames: ["error-handling"])
        let tasks = [
            makeTask(ruleName: "error-handling", filePath: "src/handler.py", focusId: "f1"),
            makeTask(ruleName: "error-handling", filePath: "src/other.py", focusId: "f2"),
            makeTask(ruleName: "naming-conventions", filePath: "src/handler.py", focusId: "f3"),
            makeTask(ruleName: "naming-conventions", filePath: "src/other.py", focusId: "f4"),
        ]

        // Act
        let filtered = tasks.filter { filter.matches($0) }

        // Assert
        #expect(filtered.count == 1)
        #expect(filtered[0].taskId == "error-handling_f1")
    }

    @Test("Filter with no matches returns empty list")
    func filterNoMatches() {
        // Arrange
        let filter = EvaluationFilter(filePath: "nonexistent.py")
        let tasks = [
            makeTask(filePath: "src/handler.py", focusId: "f1"),
            makeTask(filePath: "src/other.py", focusId: "f2"),
        ]

        // Act
        let filtered = tasks.filter { filter.matches($0) }

        // Assert
        #expect(filtered.isEmpty)
    }

    // MARK: - matches: focus area filter with task list

    @Test("Filter by focus area ID selects only that specific focus area's tasks")
    func filterTaskListByFocusArea() {
        // Arrange
        let filter = EvaluationFilter(focusAreaId: "method-handler_py-process-10-25")
        let tasks = [
            makeTask(ruleName: "rule-a", focusId: "method-handler_py-process-10-25"),
            makeTask(ruleName: "rule-b", focusId: "method-handler_py-init-1-5"),
            makeTask(ruleName: "rule-c", focusId: "method-handler_py-process-10-25"),
        ]

        // Act
        let filtered = tasks.filter { filter.matches($0) }

        // Assert
        #expect(filtered.count == 2)
        #expect(filtered.map(\.rule.name) == ["rule-a", "rule-c"])
    }

    // MARK: - init defaults

    @Test("Default init creates filter with all nil fields")
    func defaultInit() {
        // Arrange & Act
        let filter = EvaluationFilter()

        // Assert
        #expect(filter.filePath == nil)
        #expect(filter.focusAreaId == nil)
        #expect(filter.ruleNames == nil)
    }

    @Test("Partial init leaves unspecified fields as nil")
    func partialInit() {
        // Arrange & Act
        let filter = EvaluationFilter(filePath: "src/handler.py")

        // Assert
        #expect(filter.filePath == "src/handler.py")
        #expect(filter.focusAreaId == nil)
        #expect(filter.ruleNames == nil)
    }
}
