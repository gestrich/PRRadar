import Foundation
import Testing
@testable import PRRadarModels

@Suite("Evaluation Output JSON Parsing")
struct EvaluationOutputTests {

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

    // MARK: - RuleEvaluationResult

    @Test("RuleEvaluationResult decodes from Python's EvaluationResult.to_dict()")
    func ruleEvaluationResultDecode() throws {
        let json = """
        {
            "task_id": "error-handling-method-handler_py-process-10-25",
            "rule_name": "error-handling",
            "rule_file_path": "/rules/error-handling.md",
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
        #expect(result.ruleFilePath == "/rules/error-handling.md")
        #expect(result.filePath == "src/handler.py")
        #expect(result.evaluation.violatesRule == true)
        #expect(result.evaluation.score == 8)
        #expect(result.evaluation.lineNumber == 15)
        #expect(result.modelUsed == "claude-sonnet-4-20250514")
        #expect(result.durationMs == 3420)
        #expect(result.costUsd == 0.0045)
    }

    @Test("RuleEvaluationResult with null cost_usd")
    func ruleEvaluationResultNullCost() throws {
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
    }

    // MARK: - EvaluationSummary

    @Test("EvaluationSummary decodes from Python's EvaluationSummary.to_dict()")
    func evaluationSummaryDecode() throws {
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
                    "task_id": "rule-a-focus-1",
                    "rule_name": "rule-a",
                    "rule_file_path": "/rules/a.md",
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
                    "task_id": "rule-b-focus-2",
                    "rule_name": "rule-b",
                    "rule_file_path": "/rules/b.md",
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

        let summary = try JSONDecoder().decode(EvaluationSummary.self, from: json)
        #expect(summary.prNumber == 42)
        #expect(summary.evaluatedAt == "2025-01-15T10:30:00+00:00")
        #expect(summary.totalTasks == 15)
        #expect(summary.violationsFound == 3)
        #expect(summary.totalCostUsd == 0.0523)
        #expect(summary.totalDurationMs == 45000)
        #expect(summary.results.count == 2)
        #expect(summary.results[0].evaluation.violatesRule == true)
        #expect(summary.results[1].evaluation.violatesRule == false)
    }

    @Test("EvaluationSummary with empty results")
    func evaluationSummaryEmpty() throws {
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

        let summary = try JSONDecoder().decode(EvaluationSummary.self, from: json)
        #expect(summary.totalTasks == 0)
        #expect(summary.results.isEmpty)
    }

    @Test("EvaluationSummary round-trips through encode/decode")
    func evaluationSummaryRoundTrip() throws {
        let json = """
        {
            "pr_number": 10,
            "evaluated_at": "2025-03-01T12:00:00Z",
            "total_tasks": 5,
            "violations_found": 1,
            "total_cost_usd": 0.01,
            "total_duration_ms": 10000,
            "results": [
                {
                    "task_id": "t1",
                    "rule_name": "r1",
                    "rule_file_path": "/r1.md",
                    "file_path": "f.py",
                    "evaluation": {
                        "violates_rule": true,
                        "score": 5,
                        "comment": "Issue",
                        "file_path": "f.py",
                        "line_number": 1
                    },
                    "model_used": "claude-sonnet-4-20250514",
                    "duration_ms": 1000,
                    "cost_usd": 0.001
                }
            ]
        }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(EvaluationSummary.self, from: json)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvaluationSummary.self, from: encoded)

        #expect(original.prNumber == decoded.prNumber)
        #expect(original.totalTasks == decoded.totalTasks)
        #expect(original.violationsFound == decoded.violationsFound)
        #expect(original.results.count == decoded.results.count)
    }
}
