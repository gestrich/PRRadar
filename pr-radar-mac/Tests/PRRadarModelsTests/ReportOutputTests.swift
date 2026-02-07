import Foundation
import Testing
@testable import PRRadarModels

@Suite("Report Output JSON Parsing")
struct ReportOutputTests {

    // MARK: - ViolationRecord

    @Test("ViolationRecord decodes full record from Python's ViolationRecord.to_dict()")
    func violationRecordFullDecode() throws {
        let json = """
        {
            "rule_name": "error-handling",
            "score": 8,
            "file_path": "src/api/handler.py",
            "line_number": 42,
            "comment": "Unhandled exception in production code path.",
            "method_name": "process_request",
            "documentation_link": "https://docs.example.com/errors",
            "relevant_claude_skill": "swift-testing"
        }
        """.data(using: .utf8)!

        let violation = try JSONDecoder().decode(ViolationRecord.self, from: json)
        #expect(violation.ruleName == "error-handling")
        #expect(violation.score == 8)
        #expect(violation.filePath == "src/api/handler.py")
        #expect(violation.lineNumber == 42)
        #expect(violation.comment.contains("Unhandled exception"))
        #expect(violation.methodName == "process_request")
        #expect(violation.documentationLink == "https://docs.example.com/errors")
        #expect(violation.relevantClaudeSkill == "swift-testing")
    }

    @Test("ViolationRecord decodes minimal record (optional fields omitted by Python)")
    func violationRecordMinimalDecode() throws {
        let json = """
        {
            "rule_name": "naming",
            "score": 3,
            "file_path": "config.py",
            "line_number": null,
            "comment": "Consider using snake_case."
        }
        """.data(using: .utf8)!

        let violation = try JSONDecoder().decode(ViolationRecord.self, from: json)
        #expect(violation.ruleName == "naming")
        #expect(violation.lineNumber == nil)
        #expect(violation.methodName == nil)
        #expect(violation.documentationLink == nil)
        #expect(violation.relevantClaudeSkill == nil)
    }

    // MARK: - ReportSummary

    @Test("ReportSummary decodes from Python's ReportSummary.to_dict()")
    func reportSummaryDecode() throws {
        let json = """
        {
            "total_tasks_evaluated": 25,
            "violations_found": 5,
            "highest_severity": 9,
            "total_cost_usd": 0.15,
            "by_severity": {
                "Severe (8-10)": 2,
                "Moderate (5-7)": 2,
                "Minor (1-4)": 1
            },
            "by_file": {
                "src/handler.py": 3,
                "src/utils.py": 2
            },
            "by_rule": {
                "error-handling": 3,
                "naming": 2
            }
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(ReportSummary.self, from: json)
        #expect(summary.totalTasksEvaluated == 25)
        #expect(summary.violationsFound == 5)
        #expect(summary.highestSeverity == 9)
        #expect(summary.totalCostUsd == 0.15)
        #expect(summary.bySeverity["Severe (8-10)"] == 2)
        #expect(summary.bySeverity["Minor (1-4)"] == 1)
        #expect(summary.byFile["src/handler.py"] == 3)
        #expect(summary.byRule["error-handling"] == 3)
        #expect(summary.byMethod == nil)
    }

    @Test("ReportSummary decodes with by_method dictionary")
    func reportSummaryWithByMethod() throws {
        let json = """
        {
            "total_tasks_evaluated": 10,
            "violations_found": 2,
            "highest_severity": 7,
            "total_cost_usd": 0.05,
            "by_severity": {"Moderate (5-7)": 2},
            "by_file": {"main.py": 2},
            "by_rule": {"style": 2},
            "by_method": {
                "main.py": {
                    "process": [
                        {"rule_name": "style", "score": 7}
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(ReportSummary.self, from: json)
        #expect(summary.byMethod != nil)
        #expect(summary.byMethod?["main.py"] != nil)
        let processViolations = summary.byMethod?["main.py"]?["process"]
        #expect(processViolations?.count == 1)

        let firstViolation = processViolations?[0]
        #expect(firstViolation?["rule_name"] == .string("style"))
        #expect(firstViolation?["score"] == .int(7))
    }

    // MARK: - ReviewReport

    @Test("ReviewReport decodes from Python's ReviewReport.to_dict()")
    func reviewReportDecode() throws {
        let json = """
        {
            "pr_number": 42,
            "generated_at": "2025-01-15T10:30:00+00:00",
            "min_score_threshold": 5,
            "summary": {
                "total_tasks_evaluated": 15,
                "violations_found": 3,
                "highest_severity": 8,
                "total_cost_usd": 0.0523,
                "by_severity": {"Severe (8-10)": 1, "Moderate (5-7)": 2},
                "by_file": {"handler.py": 2, "utils.py": 1},
                "by_rule": {"error-handling": 2, "naming": 1}
            },
            "violations": [
                {
                    "rule_name": "error-handling",
                    "score": 8,
                    "file_path": "handler.py",
                    "line_number": 42,
                    "comment": "Critical error handling issue.",
                    "method_name": "process",
                    "documentation_link": "https://docs.example.com/errors"
                },
                {
                    "rule_name": "error-handling",
                    "score": 6,
                    "file_path": "handler.py",
                    "line_number": 78,
                    "comment": "Missing catch clause."
                },
                {
                    "rule_name": "naming",
                    "score": 5,
                    "file_path": "utils.py",
                    "line_number": 15,
                    "comment": "Variable name too short."
                }
            ]
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(ReviewReport.self, from: json)
        #expect(report.prNumber == 42)
        #expect(report.generatedAt == "2025-01-15T10:30:00+00:00")
        #expect(report.minScoreThreshold == 5)
        #expect(report.summary.totalTasksEvaluated == 15)
        #expect(report.summary.violationsFound == 3)
        #expect(report.summary.highestSeverity == 8)
        #expect(report.violations.count == 3)
        #expect(report.violations[0].ruleName == "error-handling")
        #expect(report.violations[0].score == 8)
        #expect(report.violations[0].methodName == "process")
        #expect(report.violations[1].methodName == nil)
        #expect(report.violations[2].filePath == "utils.py")
    }

    @Test("ReviewReport with no violations")
    func reviewReportNoViolations() throws {
        let json = """
        {
            "pr_number": 99,
            "generated_at": "2025-02-01T00:00:00Z",
            "min_score_threshold": 5,
            "summary": {
                "total_tasks_evaluated": 10,
                "violations_found": 0,
                "highest_severity": 0,
                "total_cost_usd": 0.03,
                "by_severity": {},
                "by_file": {},
                "by_rule": {}
            },
            "violations": []
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(ReviewReport.self, from: json)
        #expect(report.prNumber == 99)
        #expect(report.summary.violationsFound == 0)
        #expect(report.violations.isEmpty)
        #expect(report.summary.bySeverity.isEmpty)
    }

    @Test("ReviewReport round-trips through encode/decode")
    func reviewReportRoundTrip() throws {
        let json = """
        {
            "pr_number": 7,
            "generated_at": "2025-03-01T12:00:00Z",
            "min_score_threshold": 3,
            "summary": {
                "total_tasks_evaluated": 5,
                "violations_found": 1,
                "highest_severity": 6,
                "total_cost_usd": 0.01,
                "by_severity": {"Moderate (5-7)": 1},
                "by_file": {"app.py": 1},
                "by_rule": {"test-rule": 1}
            },
            "violations": [
                {
                    "rule_name": "test-rule",
                    "score": 6,
                    "file_path": "app.py",
                    "line_number": 10,
                    "comment": "Violation found."
                }
            ]
        }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(ReviewReport.self, from: json)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReviewReport.self, from: encoded)

        #expect(original.prNumber == decoded.prNumber)
        #expect(original.generatedAt == decoded.generatedAt)
        #expect(original.minScoreThreshold == decoded.minScoreThreshold)
        #expect(original.summary.totalTasksEvaluated == decoded.summary.totalTasksEvaluated)
        #expect(original.violations.count == decoded.violations.count)
        #expect(original.violations[0].ruleName == decoded.violations[0].ruleName)
    }

    // MARK: - AnyCodableValue

    @Test("AnyCodableValue decodes all supported types")
    func anyCodableValueTypes() throws {
        let stringJson = "\"hello\"".data(using: .utf8)!
        let intJson = "42".data(using: .utf8)!
        let doubleJson = "3.14".data(using: .utf8)!
        let boolJson = "true".data(using: .utf8)!
        let nullJson = "null".data(using: .utf8)!

        let string = try JSONDecoder().decode(AnyCodableValue.self, from: stringJson)
        let int = try JSONDecoder().decode(AnyCodableValue.self, from: intJson)
        let double = try JSONDecoder().decode(AnyCodableValue.self, from: doubleJson)
        let bool = try JSONDecoder().decode(AnyCodableValue.self, from: boolJson)
        let null = try JSONDecoder().decode(AnyCodableValue.self, from: nullJson)

        #expect(string == .string("hello"))
        #expect(int == .int(42))
        #expect(double == .double(3.14))
        #expect(bool == .bool(true))
        #expect(null == .null)
    }

    @Test("AnyCodableValue round-trips through encode/decode")
    func anyCodableValueRoundTrip() throws {
        let values: [AnyCodableValue] = [
            .string("test"),
            .int(99),
            .double(2.718),
            .bool(false),
            .null,
        ]

        for original in values {
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: encoded)
            #expect(original == decoded)
        }
    }
}

extension AnyCodableValue: Equatable {
    public static func == (lhs: AnyCodableValue, rhs: AnyCodableValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }
}
