import Foundation
import Testing
@testable import PRRadarModels

@Suite("Analysis Output JSON Parsing")
struct AnalysisOutputTests {

    // MARK: - RuleEvaluation

    @Test("RuleEvaluation decodes from Python's RuleEvaluation.to_dict()")
    func ruleEvaluationDecode() throws {
        let json = """
        {
            "violates_rule": true,
            "score": 7,
            "comment": "Missing error handling in async function. Wrap the await call in a try/catch block.",
            "file_path": "src/api/handler.py",
            "line_number": 42
        }
        """.data(using: .utf8)!

        let eval = try JSONDecoder().decode(RuleEvaluation.self, from: json)
        #expect(eval.violatesRule == true)
        #expect(eval.score == 7)
        #expect(eval.comment.contains("Missing error handling"))
        #expect(eval.filePath == "src/api/handler.py")
        #expect(eval.lineNumber == 42)
    }

    @Test("RuleEvaluation decodes with null line_number (no violation location)")
    func ruleEvaluationNullLineNumber() throws {
        let json = """
        {
            "violates_rule": false,
            "score": 2,
            "comment": "Code follows the naming convention correctly.",
            "file_path": "src/utils.py",
            "line_number": null
        }
        """.data(using: .utf8)!

        let eval = try JSONDecoder().decode(RuleEvaluation.self, from: json)
        #expect(eval.violatesRule == false)
        #expect(eval.score == 2)
        #expect(eval.lineNumber == nil)
    }

    @Test("RuleEvaluation decodes without line_number key (Python omits when None)")
    func ruleEvaluationMissingLineNumber() throws {
        let json = """
        {
            "violates_rule": false,
            "score": 1,
            "comment": "No issues found.",
            "file_path": "config.py"
        }
        """.data(using: .utf8)!

        let eval = try JSONDecoder().decode(RuleEvaluation.self, from: json)
        #expect(eval.lineNumber == nil)
    }

    // MARK: - RuleEvaluationResult (success)

    @Test("RuleEvaluationResult decodes success case")
    func ruleEvaluationResultDecode() throws {
        let json = """
        {
            "status": "success",
            "task_id": "error-handling-method-handler_py-process-10-25",
            "rule_name": "error-handling",
            "file_path": "src/handler.py",
            "evaluation": {
                "violates_rule": true,
                "score": 8,
                "comment": "Critical: unhandled exception in production code path.",
                "file_path": "src/handler.py",
                "line_number": 15
            },
            "model_used": "claude-sonnet-4-20250514",
            "duration_ms": 3420,
            "cost_usd": 0.0045
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleEvaluationResult.self, from: json)
        #expect(result.taskId == "error-handling-method-handler_py-process-10-25")
        #expect(result.ruleName == "error-handling")
        #expect(result.filePath == "src/handler.py")
        #expect(result.evaluation?.violatesRule == true)
        #expect(result.evaluation?.score == 8)
        #expect(result.evaluation?.lineNumber == 15)
        #expect(result.modelUsed == "claude-sonnet-4-20250514")
        #expect(result.durationMs == 3420)
        #expect(result.costUsd == 0.0045)
    }

    @Test("RuleEvaluationResult decodes legacy JSON without status field as success")
    func ruleEvaluationResultDecodeLegacy() throws {
        let json = """
        {
            "task_id": "task-1",
            "rule_name": "test-rule",
            "rule_file_path": "/rules/test.md",
            "file_path": "test.py",
            "evaluation": {
                "violates_rule": false,
                "score": 1,
                "comment": "OK",
                "file_path": "test.py"
            },
            "model_used": "claude-haiku-4-5-20251001",
            "duration_ms": 500,
            "cost_usd": null
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleEvaluationResult.self, from: json)
        #expect(result.costUsd == nil)
        #expect(result.modelUsed == "claude-haiku-4-5-20251001")
        guard case .success = result else {
            Issue.record("Expected .success case")
            return
        }
    }

    // MARK: - RuleEvaluationResult (error)

    @Test("RuleEvaluationResult decodes error case")
    func ruleEvaluationResultDecodeError() throws {
        let json = """
        {
            "status": "error",
            "task_id": "task-fail",
            "rule_name": "test-rule",
            "file_path": "src/app.swift",
            "error_message": "No response from Claude Agent for 120 seconds",
            "model_used": "claude-sonnet-4-20250514"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RuleEvaluationResult.self, from: json)
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

    // MARK: - RuleEvaluationResult round-trip

    @Test("RuleEvaluationResult success round-trips through encode/decode")
    func ruleEvaluationResultRoundTrip() throws {
        let original: RuleEvaluationResult = .success(EvaluationSuccess(
            taskId: "t1", ruleName: "r1", filePath: "f.py",
            evaluation: RuleEvaluation(violatesRule: true, score: 5, comment: "Issue", filePath: "f.py", lineNumber: 1),
            modelUsed: "claude-sonnet-4-20250514", durationMs: 1000, costUsd: 0.001
        ))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleEvaluationResult.self, from: encoded)

        #expect(original.taskId == decoded.taskId)
        #expect(original.isViolation == decoded.isViolation)
        #expect(original.costUsd == decoded.costUsd)
    }

    @Test("RuleEvaluationResult error round-trips through encode/decode")
    func ruleEvaluationResultErrorRoundTrip() throws {
        let original: RuleEvaluationResult = .error(EvaluationError(
            taskId: "t1", ruleName: "r1", filePath: "f.py",
            errorMessage: "Timeout", modelUsed: "claude-sonnet-4-20250514"
        ))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleEvaluationResult.self, from: encoded)

        guard case .error(let e) = decoded else {
            Issue.record("Expected .error case")
            return
        }
        #expect(e.errorMessage == "Timeout")
    }

    // MARK: - AnalysisSummary

    @Test("AnalysisSummary decodes from JSON")
    func analysisSummaryDecode() throws {
        let json = """
        {
            "pr_number": 42,
            "evaluated_at": "2025-01-15T10:30:00+00:00",
            "total_tasks": 15,
            "violations_found": 3,
            "total_cost_usd": 0.0523,
            "total_duration_ms": 45000,
            "results": [
                {
                    "status": "success",
                    "task_id": "rule-a-focus-1",
                    "rule_name": "rule-a",
                    "file_path": "src/main.py",
                    "evaluation": {
                        "violates_rule": true,
                        "score": 6,
                        "comment": "Moderate issue found.",
                        "file_path": "src/main.py",
                        "line_number": 30
                    },
                    "model_used": "claude-sonnet-4-20250514",
                    "duration_ms": 2500,
                    "cost_usd": 0.003
                },
                {
                    "status": "success",
                    "task_id": "rule-b-focus-2",
                    "rule_name": "rule-b",
                    "file_path": "src/utils.py",
                    "evaluation": {
                        "violates_rule": false,
                        "score": 2,
                        "comment": "Looks good.",
                        "file_path": "src/utils.py",
                        "line_number": null
                    },
                    "model_used": "claude-sonnet-4-20250514",
                    "duration_ms": 1800,
                    "cost_usd": 0.002
                }
            ]
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(AnalysisSummary.self, from: json)
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

    @Test("AnalysisSummary with empty results")
    func analysisSummaryEmpty() throws {
        let json = """
        {
            "pr_number": 1,
            "evaluated_at": "2025-02-01T00:00:00+00:00",
            "total_tasks": 0,
            "violations_found": 0,
            "total_cost_usd": 0.0,
            "total_duration_ms": 0,
            "results": []
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(AnalysisSummary.self, from: json)
        #expect(summary.totalTasks == 0)
        #expect(summary.results.isEmpty)
    }

    @Test("AnalysisSummary round-trips through encode/decode")
    func analysisSummaryRoundTrip() throws {
        let result: RuleEvaluationResult = .success(EvaluationSuccess(
            taskId: "t1", ruleName: "r1", filePath: "f.py",
            evaluation: RuleEvaluation(violatesRule: true, score: 5, comment: "Issue", filePath: "f.py", lineNumber: 1),
            modelUsed: "claude-sonnet-4-20250514", durationMs: 1000, costUsd: 0.001
        ))

        let original = AnalysisSummary(
            prNumber: 10, evaluatedAt: "2025-03-01T12:00:00Z",
            totalTasks: 5, violationsFound: 1, totalCostUsd: 0.01, totalDurationMs: 10000,
            results: [result]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnalysisSummary.self, from: encoded)

        #expect(original.prNumber == decoded.prNumber)
        #expect(original.totalTasks == decoded.totalTasks)
        #expect(original.violationsFound == decoded.violationsFound)
        #expect(original.results.count == decoded.results.count)
    }
}
