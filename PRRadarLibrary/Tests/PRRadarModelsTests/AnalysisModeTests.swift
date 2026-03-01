import Foundation
import Testing
@testable import PRRadarModels

@Suite("AnalysisMode")
struct AnalysisModeTests {

    // MARK: - Helpers

    private func makeTask(violationRegex: String? = nil) -> RuleRequest {
        RuleRequest(
            taskId: "test-task",
            rule: TaskRule(
                name: "test-rule",
                description: "Test rule",
                category: "test",
                content: "Rule content",
                violationRegex: violationRegex
            ),
            focusArea: FocusArea(
                focusId: "focus-1",
                filePath: "src/file.py",
                startLine: 1,
                endLine: 10,
                description: "focus area",
                hunkIndex: 0,
                hunkContent: "@@ content"
            ),
            gitBlobHash: "abc123"
        )
    }

    private func makeRegexTask() -> RuleRequest {
        makeTask(violationRegex: "TODO|FIXME")
    }

    private func makeAiTask() -> RuleRequest {
        makeTask(violationRegex: nil)
    }

    // MARK: - .all

    @Test("all matches regex task")
    func allMatchesRegexTask() {
        // Arrange
        let task = makeRegexTask()

        // Act
        let result = AnalysisMode.all.matches(task)

        // Assert
        #expect(result)
    }

    @Test("all matches AI task")
    func allMatchesAiTask() {
        // Arrange
        let task = makeAiTask()

        // Act
        let result = AnalysisMode.all.matches(task)

        // Assert
        #expect(result)
    }

    // MARK: - .regexOnly

    @Test("regexOnly matches task with violationRegex")
    func regexOnlyMatchesRegexTask() {
        // Arrange
        let task = makeRegexTask()

        // Act
        let result = AnalysisMode.regexOnly.matches(task)

        // Assert
        #expect(result)
    }

    @Test("regexOnly rejects task without violationRegex")
    func regexOnlyRejectsAiTask() {
        // Arrange
        let task = makeAiTask()

        // Act
        let result = AnalysisMode.regexOnly.matches(task)

        // Assert
        #expect(!result)
    }

    // MARK: - .aiOnly

    @Test("aiOnly matches task without violationRegex")
    func aiOnlyMatchesAiTask() {
        // Arrange
        let task = makeAiTask()

        // Act
        let result = AnalysisMode.aiOnly.matches(task)

        // Assert
        #expect(result)
    }

    @Test("aiOnly rejects task with violationRegex")
    func aiOnlyRejectsRegexTask() {
        // Arrange
        let task = makeRegexTask()

        // Act
        let result = AnalysisMode.aiOnly.matches(task)

        // Assert
        #expect(!result)
    }

    // MARK: - Filtering a mixed task list

    @Test("regexOnly filters to only regex tasks from a mixed list")
    func regexOnlyFiltersMixedList() {
        // Arrange
        let tasks = [
            makeRegexTask(),
            makeAiTask(),
            makeTask(violationRegex: "HACK"),
        ]

        // Act
        let filtered = tasks.filter { AnalysisMode.regexOnly.matches($0) }

        // Assert
        #expect(filtered.count == 2)
    }

    @Test("aiOnly filters to only AI tasks from a mixed list")
    func aiOnlyFiltersMixedList() {
        // Arrange
        let tasks = [
            makeRegexTask(),
            makeAiTask(),
            makeTask(violationRegex: "HACK"),
        ]

        // Act
        let filtered = tasks.filter { AnalysisMode.aiOnly.matches($0) }

        // Assert
        #expect(filtered.count == 1)
    }

    @Test("all keeps every task in a mixed list")
    func allKeepsMixedList() {
        // Arrange
        let tasks = [
            makeRegexTask(),
            makeAiTask(),
            makeTask(violationRegex: "HACK"),
        ]

        // Act
        let filtered = tasks.filter { AnalysisMode.all.matches($0) }

        // Assert
        #expect(filtered.count == 3)
    }

    // MARK: - Raw values

    @Test("raw values match expected CLI strings")
    func rawValues() {
        #expect(AnalysisMode.all.rawValue == "all")
        #expect(AnalysisMode.regexOnly.rawValue == "regex")
        #expect(AnalysisMode.aiOnly.rawValue == "ai")
    }

    @Test("init from raw value works for all cases")
    func initFromRawValue() {
        #expect(AnalysisMode(rawValue: "all") == .all)
        #expect(AnalysisMode(rawValue: "regex") == .regexOnly)
        #expect(AnalysisMode(rawValue: "ai") == .aiOnly)
        #expect(AnalysisMode(rawValue: "invalid") == nil)
    }
}
