import Foundation
import Testing
@testable import PRRadarModels

@Suite("Analysis Output JSON Parsing")
struct PRReviewResultTests {

    // MARK: - RuleResult

    @Test("RuleResult decodes with violations array")
    func ruleResultDecode() throws {
        let json = """
        {
            "taskId": "task-1",
            "ruleName": "error-handling",
            "filePath": "src/api/handler.py",
            "analysisMethod": {"type": "ai", "model": "claude-sonnet-4-20250514", "costUsd": 0.003},
            "durationMs": 1000,
            "violations": [
                {
                    "score": 7,
                    "comment": "Missing error handling in async function. Wrap the await call in a try/catch block.",
                    "filePath": "src/api/handler.py",
                    "lineNumber": 42
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleResult.self, from: json)
        #expect(result.violatesRule == true)
        #expect(result.violations.count == 1)
        #expect(result.violations[0].score == 7)
        #expect(result.violations[0].comment.contains("Missing error handling"))
        #expect(result.filePath == "src/api/handler.py")
        #expect(result.violations[0].lineNumber == 42)
    }

    @Test("RuleResult decodes with empty violations array")
    func ruleResultNoViolations() throws {
        let json = """
        {
            "taskId": "task-1",
            "ruleName": "naming",
            "filePath": "src/utils.py",
            "analysisMethod": {"type": "ai", "model": "claude-sonnet-4-20250514", "costUsd": 0.001},
            "durationMs": 1000,
            "violations": []
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleResult.self, from: json)
        #expect(result.violatesRule == false)
        #expect(result.violations.isEmpty)
    }

    @Test("RuleResult decodes with null lineNumber in violation")
    func ruleResultNullLineNumber() throws {
        let json = """
        {
            "taskId": "task-1",
            "ruleName": "naming",
            "filePath": "config.py",
            "analysisMethod": {"type": "ai", "model": "claude-sonnet-4-20250514", "costUsd": 0.001},
            "durationMs": 1000,
            "violations": [
                {
                    "score": 2,
                    "comment": "Code follows the naming convention correctly.",
                    "filePath": "config.py",
                    "lineNumber": null
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleResult.self, from: json)
        #expect(result.violations[0].lineNumber == nil)
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
                "analysisMethod": {"type": "ai", "model": "claude-sonnet-4-20250514", "costUsd": 0.0045},
                "durationMs": 3420,
                "violations": [
                    {
                        "score": 8,
                        "comment": "Critical: unhandled exception in production code path.",
                        "filePath": "src/handler.py",
                        "lineNumber": 15
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleOutcome.self, from: json)
        #expect(result.taskId == "error-handling-method-handler_py-process-10-25")
        #expect(result.ruleName == "error-handling")
        #expect(result.filePath == "src/handler.py")
        #expect(result.success?.violatesRule == true)
        #expect(result.success?.violations[0].score == 8)
        #expect(result.success?.violations[0].lineNumber == 15)
        #expect(result.analysisMethod == .ai(model: "claude-sonnet-4-20250514", costUsd: 0.0045))
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
                "analysisMethod": {"type": "ai", "model": "claude-sonnet-4-20250514", "costUsd": 0}
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
            analysisMethod: .ai(model: "claude-sonnet-4-20250514", costUsd: 0.001),
            durationMs: 1000,
            violations: [Violation(score: 5, comment: "Issue", filePath: "f.py", lineNumber: 1)]
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
            errorMessage: "Timeout", analysisMethod: .ai(model: "claude-sonnet-4-20250514", costUsd: 0)
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
            "totalDurationMs": 45000
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(PRReviewSummary.self, from: json)
        #expect(summary.prNumber == 42)
        #expect(summary.evaluatedAt == "2025-01-15T10:30:00+00:00")
        #expect(summary.totalTasks == 15)
        #expect(summary.violationsFound == 3)
        #expect(summary.totalCostUsd == 0.0523)
        #expect(summary.totalDurationMs == 45000)
    }

    @Test("PRReviewSummary with zero tasks")
    func analysisSummaryEmpty() throws {
        let json = """
        {
            "prNumber": 1,
            "evaluatedAt": "2025-02-01T00:00:00+00:00",
            "totalTasks": 0,
            "violationsFound": 0,
            "totalCostUsd": 0.0,
            "totalDurationMs": 0
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(PRReviewSummary.self, from: json)
        #expect(summary.totalTasks == 0)
    }

    @Test("PRReviewSummary round-trips through encode/decode")
    func analysisSummaryRoundTrip() throws {
        let original = PRReviewSummary(
            prNumber: 10, evaluatedAt: "2025-03-01T12:00:00Z",
            totalTasks: 5, violationsFound: 1, totalCostUsd: 0.01, totalDurationMs: 10000
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PRReviewSummary.self, from: encoded)

        #expect(original.prNumber == decoded.prNumber)
        #expect(original.totalTasks == decoded.totalTasks)
        #expect(original.violationsFound == decoded.violationsFound)
        #expect(original.totalCostUsd == decoded.totalCostUsd)
    }

    // MARK: - Multi-violation

    @Test("RuleResult with 2 violations produces 2 PRComments")
    func multipleViolationsProduceMultipleComments() throws {
        let result = RuleResult(
            taskId: "t1", ruleName: "nullability", filePath: "Cell.m",
            analysisMethod: .ai(model: "claude-sonnet-4-20250514", costUsd: 0.01),
            durationMs: 2000,
            violations: [
                Violation(score: 7, comment: "Nullable param at line 21", filePath: "Cell.m", lineNumber: 21),
                Violation(score: 6, comment: "Nullable param at line 48", filePath: "Cell.m", lineNumber: 48),
            ]
        )
        let outcome = RuleOutcome.success(result)
        let comments = outcome.violationComments(task: nil)

        #expect(comments.count == 2)
        #expect(comments[0].lineNumber == 21)
        #expect(comments[1].lineNumber == 48)
        #expect(comments[0].id == "t1_0")
        #expect(comments[1].id == "t1_1")
    }

    @Test("Empty violations array produces 0 comments and violatesRule == false")
    func emptyViolationsArray() throws {
        let result = RuleResult(
            taskId: "t1", ruleName: "naming", filePath: "utils.py",
            analysisMethod: .ai(model: "claude-sonnet-4-20250514", costUsd: 0.002),
            durationMs: 1000,
            violations: []
        )
        #expect(result.violatesRule == false)

        let outcome = RuleOutcome.success(result)
        #expect(outcome.isViolation == false)
        #expect(outcome.violationComments(task: nil).isEmpty)
    }
}
