import Foundation
import Testing
@testable import PRRadarModels

@Suite("Analysis Output JSON Parsing")
struct PRReviewResultTests {

    // MARK: - RuleResult

    @Test("RuleResult decodes with all fields")
    func ruleResultDecode() throws {
        let json = """
        {
            "taskId": "task-1",
            "ruleName": "error-handling",
            "filePath": "src/api/handler.py",
            "modelUsed": "claude-sonnet-4-20250514",
            "durationMs": 1000,
            "costUsd": 0.003,
            "violatesRule": true,
            "score": 7,
            "comment": "Missing error handling in async function. Wrap the await call in a try/catch block.",
            "lineNumber": 42
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleResult.self, from: json)
        #expect(result.violatesRule == true)
        #expect(result.score == 7)
        #expect(result.comment.contains("Missing error handling"))
        #expect(result.filePath == "src/api/handler.py")
        #expect(result.lineNumber == 42)
    }

    @Test("RuleResult decodes with null lineNumber")
    func ruleResultNullLineNumber() throws {
        let json = """
        {
            "taskId": "task-1",
            "ruleName": "naming",
            "filePath": "src/utils.py",
            "modelUsed": "claude-sonnet-4-20250514",
            "durationMs": 1000,
            "violatesRule": false,
            "score": 2,
            "comment": "Code follows the naming convention correctly.",
            "lineNumber": null
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleResult.self, from: json)
        #expect(result.violatesRule == false)
        #expect(result.score == 2)
        #expect(result.lineNumber == nil)
    }

    @Test("RuleResult decodes without lineNumber key")
    func ruleResultMissingLineNumber() throws {
        let json = """
        {
            "taskId": "task-1",
            "ruleName": "naming",
            "filePath": "config.py",
            "modelUsed": "claude-sonnet-4-20250514",
            "durationMs": 1000,
            "violatesRule": false,
            "score": 1,
            "comment": "No issues found."
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleResult.self, from: json)
        #expect(result.lineNumber == nil)
    }

    // MARK: - RuleOutcome (success)

    @Test("RuleOutcome decodes success case")
    func ruleEvaluationResultDecode() throws {
        let json = """
        {
            "success": {
                "taskId": "error-handling-method-handler_py-process-10-25",
                "ruleName": "error-handling",
                "filePath": "src/handler.py",
                "modelUsed": "claude-sonnet-4-20250514",
                "durationMs": 3420,
                "costUsd": 0.0045,
                "violatesRule": true,
                "score": 8,
                "comment": "Critical: unhandled exception in production code path.",
                "lineNumber": 15
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleOutcome.self, from: json)
        #expect(result.taskId == "error-handling-method-handler_py-process-10-25")
        #expect(result.ruleName == "error-handling")
        #expect(result.filePath == "src/handler.py")
        #expect(result.success?.violatesRule == true)
        #expect(result.success?.score == 8)
        #expect(result.success?.lineNumber == 15)
        #expect(result.modelUsed == "claude-sonnet-4-20250514")
        #expect(result.durationMs == 3420)
        #expect(result.costUsd == 0.0045)
    }

    // MARK: - RuleOutcome (error)

    @Test("RuleOutcome decodes error case")
    func ruleEvaluationResultDecodeError() throws {
        let json = """
        {
            "error": {
                "taskId": "task-fail",
                "ruleName": "test-rule",
                "filePath": "src/app.swift",
                "errorMessage": "No response from Claude Agent for 120 seconds",
                "modelUsed": "claude-sonnet-4-20250514"
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleOutcome.self, from: json)
        guard case .error(let e) = result else {
            Issue.record("Expected .error case")
            return
        }
        #expect(e.taskId == "task-fail")
        #expect(e.errorMessage == "No response from Claude Agent for 120 seconds")
        #expect(result.isViolation == false)
        #expect(result.costUsd == nil)
        #expect(result.durationMs == 0)
    }

    // MARK: - RuleOutcome round-trip

    @Test("RuleOutcome success round-trips through encode/decode")
    func ruleEvaluationResultRoundTrip() throws {
        let original: RuleOutcome = .success(RuleResult(
            taskId: "t1", ruleName: "r1", filePath: "f.py",
            modelUsed: "claude-sonnet-4-20250514", durationMs: 1000, costUsd: 0.001,
            violatesRule: true, score: 5, comment: "Issue", lineNumber: 1
        ))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleOutcome.self, from: encoded)

        #expect(original.taskId == decoded.taskId)
        #expect(original.isViolation == decoded.isViolation)
        #expect(original.costUsd == decoded.costUsd)
    }

    @Test("RuleOutcome error round-trips through encode/decode")
    func ruleEvaluationResultErrorRoundTrip() throws {
        let original: RuleOutcome = .error(RuleError(
            taskId: "t1", ruleName: "r1", filePath: "f.py",
            errorMessage: "Timeout", modelUsed: "claude-sonnet-4-20250514"
        ))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleOutcome.self, from: encoded)

        guard case .error(let e) = decoded else {
            Issue.record("Expected .error case")
            return
        }
        #expect(e.errorMessage == "Timeout")
    }

    // MARK: - PRReviewSummary

    @Test("PRReviewSummary decodes from JSON")
    func analysisSummaryDecode() throws {
        let json = """
        {
            "prNumber": 42,
            "evaluatedAt": "2025-01-15T10:30:00+00:00",
            "totalTasks": 15,
            "violationsFound": 3,
            "totalCostUsd": 0.0523,
            "totalDurationMs": 45000,
            "results": [
                {
                    "success": {
                        "taskId": "rule-a-focus-1",
                        "ruleName": "rule-a",
                        "filePath": "src/main.py",
                        "modelUsed": "claude-sonnet-4-20250514",
                        "durationMs": 2500,
                        "costUsd": 0.003,
                        "violatesRule": true,
                        "score": 6,
                        "comment": "Moderate issue found.",
                        "lineNumber": 30
                    }
                },
                {
                    "success": {
                        "taskId": "rule-b-focus-2",
                        "ruleName": "rule-b",
                        "filePath": "src/utils.py",
                        "modelUsed": "claude-sonnet-4-20250514",
                        "durationMs": 1800,
                        "costUsd": 0.002,
                        "violatesRule": false,
                        "score": 2,
                        "comment": "Looks good.",
                        "lineNumber": null
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(PRReviewSummary.self, from: json)
        #expect(summary.prNumber == 42)
        #expect(summary.evaluatedAt == "2025-01-15T10:30:00+00:00")
        #expect(summary.totalTasks == 15)
        #expect(summary.violationsFound == 3)
        #expect(summary.totalCostUsd == 0.0523)
        #expect(summary.totalDurationMs == 45000)
        #expect(summary.results.count == 2)
        #expect(summary.results[0].isViolation == true)
        #expect(summary.results[1].isViolation == false)
    }

    @Test("PRReviewSummary with empty results")
    func analysisSummaryEmpty() throws {
        let json = """
        {
            "prNumber": 1,
            "evaluatedAt": "2025-02-01T00:00:00+00:00",
            "totalTasks": 0,
            "violationsFound": 0,
            "totalCostUsd": 0.0,
            "totalDurationMs": 0,
            "results": []
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(PRReviewSummary.self, from: json)
        #expect(summary.totalTasks == 0)
        #expect(summary.results.isEmpty)
    }

    @Test("PRReviewSummary round-trips through encode/decode")
    func analysisSummaryRoundTrip() throws {
        let result: RuleOutcome = .success(RuleResult(
            taskId: "t1", ruleName: "r1", filePath: "f.py",
            modelUsed: "claude-sonnet-4-20250514", durationMs: 1000, costUsd: 0.001,
            violatesRule: true, score: 5, comment: "Issue", lineNumber: 1
        ))

        let original = PRReviewSummary(
            prNumber: 10, evaluatedAt: "2025-03-01T12:00:00Z",
            totalTasks: 5, violationsFound: 1, totalCostUsd: 0.01, totalDurationMs: 10000,
            results: [result]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PRReviewSummary.self, from: encoded)

        #expect(original.prNumber == decoded.prNumber)
        #expect(original.totalTasks == decoded.totalTasks)
        #expect(original.violationsFound == decoded.violationsFound)
        #expect(original.results.count == decoded.results.count)
    }
}
