import Foundation
import Testing
@testable import PRRadarModels

@Suite("Task Output JSON Parsing")
struct TaskOutputTests {

    // MARK: - TaskRule

    @Test("TaskRule decodes subset of rule fields from EvaluationTask.to_dict()")
    func taskRuleDecode() throws {
        let json = """
        {
            "name": "error-handling",
            "description": "Check error handling patterns",
            "category": "reliability",
            "model": "claude-sonnet-4-20250514",
            "content": "# Error Handling Rule\\n\\nEnsure all errors are caught...",
            "documentation_link": "https://docs.example.com/errors"
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(TaskRule.self, from: json)
        #expect(rule.name == "error-handling")
        #expect(rule.description == "Check error handling patterns")
        #expect(rule.category == "reliability")
        #expect(rule.model == "claude-sonnet-4-20250514")
        #expect(rule.content.contains("Error Handling Rule"))
        #expect(rule.documentationLink == "https://docs.example.com/errors")
    }

    @Test("TaskRule decodes with null model and no documentation_link")
    func taskRuleMinimal() throws {
        let json = """
        {
            "name": "naming",
            "description": "Naming conventions",
            "category": "style",
            "model": null,
            "content": "Use descriptive names"
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(TaskRule.self, from: json)
        #expect(rule.name == "naming")
        #expect(rule.model == nil)
        #expect(rule.documentationLink == nil)
    }

    // MARK: - AnalysisTaskOutput

    @Test("AnalysisTaskOutput decodes from Python's EvaluationTask.to_dict()")
    func evaluationTaskOutputDecode() throws {
        let json = """
        {
            "task_id": "error-handling-method-handler_py-process-10-25",
            "rule": {
                "name": "error-handling",
                "description": "Check error handling",
                "category": "reliability",
                "model": "claude-sonnet-4-20250514",
                "content": "Ensure proper error handling..."
            },
            "focus_area": {
                "focus_id": "method-handler_py-process-10-25",
                "file_path": "src/handler.py",
                "start_line": 10,
                "end_line": 25,
                "description": "process method",
                "hunk_index": 0,
                "hunk_content": "@@ -10,5 +10,10 @@\\n def process():",
                "focus_type": "method"
            },
            "git_blob_hash": "abc123def456789"
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(AnalysisTaskOutput.self, from: json)
        #expect(task.taskId == "error-handling-method-handler_py-process-10-25")
        #expect(task.rule.name == "error-handling")
        #expect(task.rule.category == "reliability")
        #expect(task.focusArea.filePath == "src/handler.py")
        #expect(task.focusArea.startLine == 10)
        #expect(task.focusArea.focusType == .method)
        #expect(task.gitBlobHash == "abc123def456789")
    }

    @Test("AnalysisTaskOutput with documentation_link in rule")
    func evaluationTaskWithDocs() throws {
        let json = """
        {
            "task_id": "docs-rule-file-readme-1-100",
            "rule": {
                "name": "docs-rule",
                "description": "Documentation required",
                "category": "documentation",
                "model": null,
                "content": "All public APIs need docs",
                "documentation_link": "https://example.com/docs-guide"
            },
            "focus_area": {
                "focus_id": "file-readme-1-100",
                "file_path": "README.md",
                "start_line": 1,
                "end_line": 100,
                "description": "README changes",
                "hunk_index": 0,
                "hunk_content": "@@ -1,5 +1,10 @@\\n # README",
                "focus_type": "file"
            },
            "git_blob_hash": "fedcba987654321"
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(AnalysisTaskOutput.self, from: json)
        #expect(task.rule.documentationLink == "https://example.com/docs-guide")
        #expect(task.rule.model == nil)
        #expect(task.focusArea.focusType == .file)
        #expect(task.gitBlobHash == "fedcba987654321")
    }

    @Test("AnalysisTaskOutput round-trips through encode/decode")
    func evaluationTaskRoundTrip() throws {
        let json = """
        {
            "task_id": "test-task-id",
            "rule": {
                "name": "test-rule",
                "description": "Test",
                "category": "test",
                "model": null,
                "content": "Test content"
            },
            "focus_area": {
                "focus_id": "test-focus",
                "file_path": "test.py",
                "start_line": 1,
                "end_line": 5,
                "description": "Test area",
                "hunk_index": 0,
                "hunk_content": "@@ -1,3 +1,4 @@",
                "focus_type": "file"
            },
            "git_blob_hash": "roundtrip123"
        }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(AnalysisTaskOutput.self, from: json)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnalysisTaskOutput.self, from: encoded)

        #expect(original.taskId == decoded.taskId)
        #expect(original.rule.name == decoded.rule.name)
        #expect(original.focusArea.focusId == decoded.focusArea.focusId)
        #expect(original.gitBlobHash == decoded.gitBlobHash)
    }
}
