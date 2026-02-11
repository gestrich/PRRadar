import Foundation
import Testing
@testable import PRRadarModels

@Suite("Task Model Behavior")
struct TaskBehaviorTests {

    // MARK: - TaskRule init

    @Test("TaskRule memberwise init sets all fields")
    func taskRuleInit() {
        let rule = TaskRule(
            name: "error-handling",
            description: "Check errors",
            category: "reliability",
            model: "claude-sonnet-4-20250514",
            content: "Rule body",
            documentationLink: "https://example.com"
        )

        #expect(rule.name == "error-handling")
        #expect(rule.description == "Check errors")
        #expect(rule.category == "reliability")
        #expect(rule.model == "claude-sonnet-4-20250514")
        #expect(rule.content == "Rule body")
        #expect(rule.documentationLink == "https://example.com")
    }

    @Test("TaskRule init with defaults")
    func taskRuleDefaults() {
        let rule = TaskRule(
            name: "test",
            description: "test",
            category: "test",
            content: "test content"
        )

        #expect(rule.model == nil)
        #expect(rule.documentationLink == nil)
    }

    // MARK: - AnalysisTaskOutput init

    @Test("AnalysisTaskOutput memberwise init sets all fields")
    func evaluationTaskInit() {
        let taskRule = TaskRule(
            name: "test-rule",
            description: "Test",
            category: "test",
            content: "Content"
        )
        let focusArea = FocusArea(
            focusId: "method-main-foo-1-10",
            filePath: "main.swift",
            startLine: 1,
            endLine: 10,
            description: "foo",
            hunkIndex: 0,
            hunkContent: "@@ content"
        )

        let task = AnalysisTaskOutput(
            taskId: "test-rule_method-main-foo-1-10",
            rule: taskRule,
            focusArea: focusArea,
            gitBlobHash: "abc123def456"
        )

        #expect(task.taskId == "test-rule_method-main-foo-1-10")
        #expect(task.rule.name == "test-rule")
        #expect(task.focusArea.focusId == "method-main-foo-1-10")
        #expect(task.gitBlobHash == "abc123def456")
    }

    // MARK: - AnalysisTaskOutput.from factory

    @Test("from(rule:focusArea:) creates task with correct ID and rule subset")
    func evaluationTaskFromFactory() {
        let rule = ReviewRule(
            name: "error-handling",
            filePath: "/rules/error-handling.md",
            description: "Check error handling",
            category: "reliability",
            focusType: .method,
            content: "# Error Handling\nEnsure try/catch...",
            model: "claude-sonnet-4-20250514",
            documentationLink: "https://example.com",
            relevantClaudeSkill: "swift-testing",
            ruleUrl: "https://github.com/org/rules",
            appliesTo: AppliesTo(filePatterns: ["*.swift"]),
            grep: GrepPatterns(any: ["async"])
        )

        let focusArea = FocusArea(
            focusId: "method-main-fetch-10-20",
            filePath: "main.swift",
            startLine: 10,
            endLine: 20,
            description: "fetch method",
            hunkIndex: 0,
            hunkContent: "@@ content"
        )

        let task = AnalysisTaskOutput.from(rule: rule, focusArea: focusArea, gitBlobHash: "a1b2c3d4e5f6")

        // Task ID is rule name + focus ID
        #expect(task.taskId == "error-handling_method-main-fetch-10-20")

        // TaskRule contains subset of ReviewRule fields
        #expect(task.rule.name == "error-handling")
        #expect(task.rule.description == "Check error handling")
        #expect(task.rule.category == "reliability")
        #expect(task.rule.model == "claude-sonnet-4-20250514")
        #expect(task.rule.content == "# Error Handling\nEnsure try/catch...")
        #expect(task.rule.documentationLink == "https://example.com")

        // Focus area is preserved
        #expect(task.focusArea.focusId == "method-main-fetch-10-20")
        #expect(task.focusArea.filePath == "main.swift")

        // Git blob hash is stored
        #expect(task.gitBlobHash == "a1b2c3d4e5f6")
    }

    @Test("from(rule:focusArea:) with minimal rule")
    func evaluationTaskFromMinimalRule() {
        let rule = ReviewRule(
            name: "simple",
            filePath: "/rules/simple.md",
            description: "Simple rule",
            category: "style",
            content: "Content"
        )

        let focusArea = FocusArea(
            focusId: "file-test-1-5",
            filePath: "test.swift",
            startLine: 1,
            endLine: 5,
            description: "test file",
            hunkIndex: 0,
            hunkContent: "@@ content"
        )

        let task = AnalysisTaskOutput.from(rule: rule, focusArea: focusArea, gitBlobHash: "deadbeef")

        #expect(task.taskId == "simple_file-test-1-5")
        #expect(task.rule.model == nil)
        #expect(task.rule.documentationLink == nil)
        #expect(task.gitBlobHash == "deadbeef")
    }

    // MARK: - JSON round-trip

    @Test("AnalysisTaskOutput round-trips through JSON with gitBlobHash")
    func evaluationTaskJsonRoundTrip() throws {
        // Arrange
        let taskRule = TaskRule(
            name: "error-handling",
            description: "Check errors",
            category: "reliability",
            model: "claude-sonnet-4-20250514",
            content: "Rule body",
            documentationLink: "https://example.com",
            relevantClaudeSkill: "swift-testing",
            ruleUrl: "https://github.com/org/rules"
        )
        let focusArea = FocusArea(
            focusId: "method-main-fetch-10-20",
            filePath: "Sources/main.swift",
            startLine: 10,
            endLine: 20,
            description: "fetch method",
            hunkIndex: 0,
            hunkContent: "@@ content"
        )
        let original = AnalysisTaskOutput(
            taskId: "error-handling_method-main-fetch-10-20",
            rule: taskRule,
            focusArea: focusArea,
            gitBlobHash: "a1b2c3d4e5f67890"
        )

        // Act
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(AnalysisTaskOutput.self, from: data)

        // Assert
        #expect(decoded == original)
        #expect(decoded.gitBlobHash == "a1b2c3d4e5f67890")
    }
}
