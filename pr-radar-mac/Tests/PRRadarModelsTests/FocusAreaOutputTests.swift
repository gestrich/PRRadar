import Foundation
import Testing
@testable import PRRadarModels

@Suite("FocusArea JSON Parsing")
struct FocusAreaOutputTests {

    // MARK: - FocusType

    @Test("FocusType decodes file and method values")
    func focusTypeDecode() throws {
        let fileJson = "\"file\"".data(using: .utf8)!
        let methodJson = "\"method\"".data(using: .utf8)!

        let file = try JSONDecoder().decode(FocusType.self, from: fileJson)
        let method = try JSONDecoder().decode(FocusType.self, from: methodJson)

        #expect(file == .file)
        #expect(method == .method)
    }

    // MARK: - FocusArea

    @Test("FocusArea decodes from Python's FocusArea.to_dict()")
    func focusAreaDecode() throws {
        let json = """
        {
            "focus_id": "method-handler_py-process_request-10-25",
            "file_path": "src/api/handler.py",
            "start_line": 10,
            "end_line": 25,
            "description": "Modified process_request method: adds input validation",
            "hunk_index": 0,
            "hunk_content": "@@ -10,8 +10,12 @@\\n def process_request(self, data):\\n+    if not data:\\n+        raise ValueError('Empty data')",
            "focus_type": "method"
        }
        """.data(using: .utf8)!

        let area = try JSONDecoder().decode(FocusArea.self, from: json)
        #expect(area.focusId == "method-handler_py-process_request-10-25")
        #expect(area.filePath == "src/api/handler.py")
        #expect(area.startLine == 10)
        #expect(area.endLine == 25)
        #expect(area.description == "Modified process_request method: adds input validation")
        #expect(area.hunkIndex == 0)
        #expect(area.hunkContent.contains("process_request"))
        #expect(area.focusType == .method)
    }

    @Test("FocusArea with file focus type")
    func focusAreaFileType() throws {
        let json = """
        {
            "focus_id": "file-config_py-1-50",
            "file_path": "config.py",
            "start_line": 1,
            "end_line": 50,
            "description": "Configuration file changes",
            "hunk_index": 0,
            "hunk_content": "@@ -1,10 +1,15 @@\\n # Config\\n+NEW_SETTING = True",
            "focus_type": "file"
        }
        """.data(using: .utf8)!

        let area = try JSONDecoder().decode(FocusArea.self, from: json)
        #expect(area.focusType == .file)
        #expect(area.focusId == "file-config_py-1-50")
    }

    @Test("FocusArea round-trips through encode/decode")
    func focusAreaRoundTrip() throws {
        let json = """
        {
            "focus_id": "method-test-1-10",
            "file_path": "test.py",
            "start_line": 1,
            "end_line": 10,
            "description": "Test method",
            "hunk_index": 2,
            "hunk_content": "@@ -1,5 +1,6 @@\\n+new",
            "focus_type": "method"
        }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(FocusArea.self, from: json)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FocusArea.self, from: encoded)

        #expect(original.focusId == decoded.focusId)
        #expect(original.filePath == decoded.filePath)
        #expect(original.startLine == decoded.startLine)
        #expect(original.endLine == decoded.endLine)
        #expect(original.focusType == decoded.focusType)
    }

    // MARK: - FocusAreaTypeOutput

    @Test("FocusAreaTypeOutput decodes from per-type JSON file (e.g. method.json)")
    func focusAreaTypeOutputDecode() throws {
        let json = """
        {
            "pr_number": 42,
            "generated_at": "2025-01-15T10:30:00+00:00",
            "focus_type": "method",
            "focus_areas": [
                {
                    "focus_id": "method-main_py-foo-5-15",
                    "file_path": "main.py",
                    "start_line": 5,
                    "end_line": 15,
                    "description": "New foo function",
                    "hunk_index": 0,
                    "hunk_content": "@@ -5,3 +5,8 @@\\n+def foo():",
                    "focus_type": "method"
                },
                {
                    "focus_id": "method-main_py-bar-20-30",
                    "file_path": "main.py",
                    "start_line": 20,
                    "end_line": 30,
                    "description": "Modified bar function",
                    "hunk_index": 1,
                    "hunk_content": "@@ -20,5 +20,8 @@\\n def bar():\\n+    return 42",
                    "focus_type": "method"
                }
            ],
            "total_hunks_processed": 3,
            "generation_cost_usd": 0.0012
        }
        """.data(using: .utf8)!

        let output = try JSONDecoder().decode(FocusAreaTypeOutput.self, from: json)
        #expect(output.prNumber == 42)
        #expect(output.generatedAt == "2025-01-15T10:30:00+00:00")
        #expect(output.focusType == "method")
        #expect(output.focusAreas.count == 2)
        #expect(output.totalHunksProcessed == 3)
        #expect(output.generationCostUsd == 0.0012)
        #expect(output.focusAreas[0].focusId == "method-main_py-foo-5-15")
    }

    @Test("FocusAreaTypeOutput with empty focus areas")
    func focusAreaTypeOutputEmpty() throws {
        let json = """
        {
            "pr_number": 99,
            "generated_at": "2025-02-01T00:00:00+00:00",
            "focus_type": "file",
            "focus_areas": [],
            "total_hunks_processed": 0,
            "generation_cost_usd": 0.0
        }
        """.data(using: .utf8)!

        let output = try JSONDecoder().decode(FocusAreaTypeOutput.self, from: json)
        #expect(output.prNumber == 99)
        #expect(output.focusAreas.isEmpty)
        #expect(output.generationCostUsd == 0.0)
    }
}
