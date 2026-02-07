import Foundation
import Testing
@testable import PRRadarModels

@Suite("DiffOutput JSON Parsing")
struct DiffOutputTests {

    // MARK: - ParsedHunk

    @Test("ParsedHunk decodes from Python's Hunk.to_dict()")
    func parsedHunkDecode() throws {
        let json = """
        {
            "file_path": "src/api/handler.py",
            "content": "diff --git a/src/api/handler.py b/src/api/handler.py\\n@@ -10,3 +10,4 @@\\n context\\n+added line",
            "old_start": 10,
            "old_length": 3,
            "new_start": 10,
            "new_length": 4
        }
        """.data(using: .utf8)!

        let hunk = try JSONDecoder().decode(ParsedHunk.self, from: json)
        #expect(hunk.filePath == "src/api/handler.py")
        #expect(hunk.oldStart == 10)
        #expect(hunk.oldLength == 3)
        #expect(hunk.newStart == 10)
        #expect(hunk.newLength == 4)
        #expect(hunk.content.contains("added line"))
    }

    @Test("ParsedHunk round-trips through encode/decode")
    func parsedHunkRoundTrip() throws {
        let json = """
        {
            "file_path": "test.swift",
            "content": "@@ -1,2 +1,3 @@\\n context\\n+new",
            "old_start": 1,
            "old_length": 2,
            "new_start": 1,
            "new_length": 3
        }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(ParsedHunk.self, from: json)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParsedHunk.self, from: encoded)

        #expect(original.filePath == decoded.filePath)
        #expect(original.content == decoded.content)
        #expect(original.oldStart == decoded.oldStart)
        #expect(original.oldLength == decoded.oldLength)
        #expect(original.newStart == decoded.newStart)
        #expect(original.newLength == decoded.newLength)
    }

    // MARK: - PRDiffOutput

    @Test("PRDiffOutput decodes from Python's GitDiff.to_dict()")
    func prDiffOutputDecode() throws {
        let json = """
        {
            "commit_hash": "abc123def456",
            "hunks": [
                {
                    "file_path": "src/main.py",
                    "content": "@@ -1,5 +1,6 @@\\n def main():\\n+    print('hello')",
                    "old_start": 1,
                    "old_length": 5,
                    "new_start": 1,
                    "new_length": 6
                },
                {
                    "file_path": "src/utils.py",
                    "content": "@@ -20,3 +20,4 @@\\n def helper():\\n+    return True",
                    "old_start": 20,
                    "old_length": 3,
                    "new_start": 20,
                    "new_length": 4
                }
            ]
        }
        """.data(using: .utf8)!

        let diff = try JSONDecoder().decode(PRDiffOutput.self, from: json)
        #expect(diff.commitHash == "abc123def456")
        #expect(diff.hunks.count == 2)
        #expect(diff.hunks[0].filePath == "src/main.py")
        #expect(diff.hunks[1].filePath == "src/utils.py")
    }

    @Test("PRDiffOutput with empty hunks array")
    func prDiffOutputEmptyHunks() throws {
        let json = """
        {
            "commit_hash": "deadbeef",
            "hunks": []
        }
        """.data(using: .utf8)!

        let diff = try JSONDecoder().decode(PRDiffOutput.self, from: json)
        #expect(diff.commitHash == "deadbeef")
        #expect(diff.hunks.isEmpty)
    }

    @Test("EffectiveDiffOutput is a typealias for PRDiffOutput")
    func effectiveDiffOutputAlias() throws {
        let json = """
        {
            "commit_hash": "eff1c1ent",
            "hunks": [
                {
                    "file_path": "clean.swift",
                    "content": "@@ -1,1 +1,2 @@\\n+new line",
                    "old_start": 1,
                    "old_length": 1,
                    "new_start": 1,
                    "new_length": 2
                }
            ]
        }
        """.data(using: .utf8)!

        let effective = try JSONDecoder().decode(EffectiveDiffOutput.self, from: json)
        #expect(effective.commitHash == "eff1c1ent")
        #expect(effective.hunks.count == 1)
    }

    // MARK: - MoveDetail

    @Test("MoveDetail decodes from Python's effective diff moves")
    func moveDetailDecode() throws {
        let json = """
        {
            "source_file": "old_module.py",
            "target_file": "new_module.py",
            "source_lines": [10, 11, 12, 13, 14],
            "target_lines": [25, 26, 27, 28, 29],
            "matched_lines": 5,
            "score": 0.95,
            "effective_diff_lines": 2
        }
        """.data(using: .utf8)!

        let move = try JSONDecoder().decode(MoveDetail.self, from: json)
        #expect(move.sourceFile == "old_module.py")
        #expect(move.targetFile == "new_module.py")
        #expect(move.sourceLines == [10, 11, 12, 13, 14])
        #expect(move.targetLines == [25, 26, 27, 28, 29])
        #expect(move.matchedLines == 5)
        #expect(move.score == 0.95)
        #expect(move.effectiveDiffLines == 2)
    }

    // MARK: - MoveReport

    @Test("MoveReport decodes from effective-diff-moves.json")
    func moveReportDecode() throws {
        let json = """
        {
            "moves_detected": 2,
            "total_lines_moved": 15,
            "total_lines_effectively_changed": 8,
            "moves": [
                {
                    "source_file": "a.py",
                    "target_file": "b.py",
                    "source_lines": [1, 2, 3],
                    "target_lines": [10, 11, 12],
                    "matched_lines": 3,
                    "score": 0.85,
                    "effective_diff_lines": 1
                },
                {
                    "source_file": "c.py",
                    "target_file": "d.py",
                    "source_lines": [5, 6],
                    "target_lines": [20, 21],
                    "matched_lines": 2,
                    "score": 1.0,
                    "effective_diff_lines": 0
                }
            ]
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(MoveReport.self, from: json)
        #expect(report.movesDetected == 2)
        #expect(report.totalLinesMoved == 15)
        #expect(report.totalLinesEffectivelyChanged == 8)
        #expect(report.moves.count == 2)
        #expect(report.moves[0].sourceFile == "a.py")
        #expect(report.moves[1].score == 1.0)
    }

    @Test("MoveReport with no moves")
    func moveReportEmpty() throws {
        let json = """
        {
            "moves_detected": 0,
            "total_lines_moved": 0,
            "total_lines_effectively_changed": 0,
            "moves": []
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(MoveReport.self, from: json)
        #expect(report.movesDetected == 0)
        #expect(report.moves.isEmpty)
    }

    @Test("MoveReport round-trips through encode/decode")
    func moveReportRoundTrip() throws {
        let json = """
        {
            "moves_detected": 1,
            "total_lines_moved": 5,
            "total_lines_effectively_changed": 3,
            "moves": [
                {
                    "source_file": "src.py",
                    "target_file": "dst.py",
                    "source_lines": [1, 2],
                    "target_lines": [10, 11],
                    "matched_lines": 2,
                    "score": 0.9,
                    "effective_diff_lines": 1
                }
            ]
        }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(MoveReport.self, from: json)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MoveReport.self, from: encoded)

        #expect(original.movesDetected == decoded.movesDetected)
        #expect(original.totalLinesMoved == decoded.totalLinesMoved)
        #expect(original.moves.count == decoded.moves.count)
        #expect(original.moves[0].sourceFile == decoded.moves[0].sourceFile)
    }
}
