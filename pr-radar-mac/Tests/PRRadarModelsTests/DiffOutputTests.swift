import Foundation
import Testing
@testable import PRRadarModels

@Suite("DiffOutput JSON Parsing")
struct DiffOutputTests {

    // MARK: - GitDiff round-trip

    @Test("GitDiff round-trips through encode/decode")
    func gitDiffRoundTrip() throws {
        let diff = GitDiff(
            rawContent: "@@ -1,2 +1,3 @@\n context\n+new",
            hunks: [
                Hunk(
                    filePath: "test.swift",
                    content: "@@ -1,2 +1,3 @@\n context\n+new",
                    rawHeader: ["diff --git a/test.swift b/test.swift"],
                    oldStart: 1,
                    oldLength: 2,
                    newStart: 1,
                    newLength: 3
                )
            ],
            commitHash: "abc123"
        )

        let encoded = try JSONEncoder().encode(diff)
        let decoded = try JSONDecoder().decode(GitDiff.self, from: encoded)

        #expect(decoded.commitHash == "abc123")
        #expect(decoded.hunks.count == 1)
        #expect(decoded.hunks[0].filePath == "test.swift")
        #expect(decoded.hunks[0].oldStart == 1)
        #expect(decoded.hunks[0].newLength == 3)
    }

    @Test("GitDiff with empty hunks array")
    func gitDiffEmptyHunks() throws {
        let diff = GitDiff(rawContent: "", hunks: [], commitHash: "deadbeef")

        let encoded = try JSONEncoder().encode(diff)
        let decoded = try JSONDecoder().decode(GitDiff.self, from: encoded)

        #expect(decoded.commitHash == "deadbeef")
        #expect(decoded.hunks.isEmpty)
    }

    // MARK: - MoveDetail

    @Test("MoveDetail decodes from effective diff moves")
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
