import Foundation
import Testing
@testable import PRRadarModels

// MARK: - Helpers

private func makeRemoved(_ filePath: String, _ lineNumber: Int, _ content: String, hunkIndex: Int = 0) -> TaggedLine {
    TaggedLine(
        content: content,
        normalized: content.trimmingCharacters(in: .whitespaces),
        filePath: filePath,
        lineNumber: lineNumber,
        hunkIndex: hunkIndex,
        lineType: .removed
    )
}

private func makeAdded(_ filePath: String, _ lineNumber: Int, _ content: String, hunkIndex: Int = 1) -> TaggedLine {
    TaggedLine(
        content: content,
        normalized: content.trimmingCharacters(in: .whitespaces),
        filePath: filePath,
        lineNumber: lineNumber,
        hunkIndex: hunkIndex,
        lineType: .added
    )
}

private func makeCandidate(
    sourceFile: String,
    targetFile: String,
    removedLines: [(Int, String)],
    addedLines: [(Int, String)],
    score: Double = 0.5
) -> MoveCandidate {
    let removed = removedLines.map { makeRemoved(sourceFile, $0.0, $0.1) }
    let added = addedLines.map { makeAdded(targetFile, $0.0, $0.1) }
    return MoveCandidate(
        removedLines: removed,
        addedLines: added,
        score: score,
        sourceFile: sourceFile,
        targetFile: targetFile,
        sourceStartLine: removed[0].lineNumber,
        targetStartLine: added[0].lineNumber
    )
}

/// Git-based rediff for tests: writes temp files and calls `git diff --no-index`.
private func gitRediff(_ oldText: String, _ newText: String, _ oldLabel: String, _ newLabel: String) throws -> String {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let oldPath = tmpDir.appendingPathComponent("old.txt")
    let newPath = tmpDir.appendingPathComponent("new.txt")
    try oldText.write(to: oldPath, atomically: true, encoding: .utf8)
    try newText.write(to: newPath, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["diff", "--no-index", "--no-color", oldPath.path, newPath.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    var raw = String(data: data, encoding: .utf8) ?? ""

    if raw.isEmpty { return "" }

    let oldRel = String(oldPath.path.dropFirst())
    let newRel = String(newPath.path.dropFirst())
    raw = raw.replacingOccurrences(of: "a/\(oldRel)", with: "a/\(oldLabel)")
    raw = raw.replacingOccurrences(of: "b/\(newRel)", with: "b/\(newLabel)")

    return raw
}

// MARK: - Tests: extractLineRange

@Suite struct ExtractLineRangeTests {

    @Test func extractMiddleLines() {
        let content = "line1\nline2\nline3\nline4\nline5\n"
        let result = extractLineRange(from: content, start: 2, end: 4)
        #expect(result == "line2\nline3\nline4\n")
    }

    @Test func extractFirstLine() {
        let content = "line1\nline2\nline3\n"
        let result = extractLineRange(from: content, start: 1, end: 1)
        #expect(result == "line1\n")
    }

    @Test func extractLastLine() {
        let content = "line1\nline2\nline3\n"
        let result = extractLineRange(from: content, start: 3, end: 3)
        #expect(result == "line3\n")
    }

    @Test func extractAllLines() {
        let content = "line1\nline2\nline3\n"
        let result = extractLineRange(from: content, start: 1, end: 3)
        #expect(result == "line1\nline2\nline3\n")
    }

    @Test func clampStartBelowOne() {
        let content = "line1\nline2\nline3\n"
        let result = extractLineRange(from: content, start: -5, end: 2)
        #expect(result == "line1\nline2\n")
    }

    @Test func clampEndBeyondFile() {
        let content = "line1\nline2\nline3\n"
        let result = extractLineRange(from: content, start: 2, end: 100)
        #expect(result == "line2\nline3\n")
    }

    @Test func startBeyondFileReturnsEmpty() {
        let content = "line1\nline2\n"
        let result = extractLineRange(from: content, start: 10, end: 20)
        #expect(result == "")
    }

    @Test func emptyContentReturnsEmpty() {
        let result = extractLineRange(from: "", start: 1, end: 5)
        #expect(result == "")
    }
}

// MARK: - Tests: extendBlockRange

@Suite struct ExtendBlockRangeTests {

    @Test func defaultContext() {
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(25, "x"), (26, "y"), (27, "z")],
            addedLines: [(10, "x"), (11, "y"), (12, "z")]
        )
        let ranges = extendBlockRange(candidate)
        #expect(ranges.source.start == 25 - defaultContextLines)
        #expect(ranges.source.end == 27 + defaultContextLines)
        #expect(ranges.target.start == 1) // clamped: 10 - 20 < 1
        #expect(ranges.target.end == 12 + defaultContextLines)
    }

    @Test func smallContext() {
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(5, "x"), (6, "y"), (7, "z")],
            addedLines: [(5, "x"), (6, "y"), (7, "z")]
        )
        let ranges = extendBlockRange(candidate, contextLines: 2)
        #expect(ranges.source.start == 3)
        #expect(ranges.source.end == 9)
        #expect(ranges.target.start == 3)
        #expect(ranges.target.end == 9)
    }

    @Test func clampStartToOne() {
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(2, "x"), (3, "y")],
            addedLines: [(1, "x"), (2, "y")]
        )
        let ranges = extendBlockRange(candidate, contextLines: 10)
        #expect(ranges.source.start == 1)
        #expect(ranges.target.start == 1)
    }

    @Test func zeroContext() {
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(10, "x"), (11, "y"), (12, "z")],
            addedLines: [(20, "x"), (21, "y"), (22, "z")]
        )
        let ranges = extendBlockRange(candidate, contextLines: 0)
        #expect(ranges.source.start == 10)
        #expect(ranges.source.end == 12)
        #expect(ranges.target.start == 20)
        #expect(ranges.target.end == 22)
    }
}

// MARK: - Tests: rediff (via git diff --no-index)

@Suite struct RediffRegionsTests {

    @Test func identicalRegionsProduceEmptyDiff() throws {
        let text = "line1\nline2\nline3\n"
        let result = try gitRediff(text, text, "a.py", "b.py")
        #expect(result == "")
    }

    @Test func differentRegionsProduceDiff() throws {
        let old = "line1\nline2\nline3\n"
        let new = "line1\nchanged\nline3\n"
        let result = try gitRediff(old, new, "old.py", "new.py")
        #expect(result.contains("-line2"))
        #expect(result.contains("+changed"))
    }

    @Test func filePathsAreRelabeled() throws {
        let old = "line1\n"
        let new = "line2\n"
        let result = try gitRediff(old, new, "utils.py", "helpers.py")
        #expect(result.contains("a/utils.py"))
        #expect(result.contains("b/helpers.py"))
    }

    @Test func addedLinesAppearInDiff() throws {
        let old = "line1\nline2\n"
        let new = "line1\nnew_line\nline2\n"
        let result = try gitRediff(old, new, "a.py", "b.py")
        #expect(result.contains("+new_line"))
    }

    @Test func removedLinesAppearInDiff() throws {
        let old = "line1\nold_line\nline2\n"
        let new = "line1\nline2\n"
        let result = try gitRediff(old, new, "a.py", "b.py")
        #expect(result.contains("-old_line"))
    }

    @Test func emptyInputs() throws {
        let result = try gitRediff("", "", "a.py", "b.py")
        #expect(result == "")
    }
}

// MARK: - Tests: hunkOverlapsBlock / trimHunks

@Suite struct HunkOverlapsBlockTests {

    private func makeHunk(newStart: Int, newLength: Int) -> Hunk {
        Hunk(
            filePath: "test.py",
            content: "",
            oldStart: newStart,
            oldLength: newLength,
            newStart: newStart,
            newLength: newLength
        )
    }

    @Test func hunkInsideBlock() {
        let hunk = makeHunk(newStart: 5, newLength: 3)
        #expect(hunkOverlapsBlock(hunk, blockStart: 12, blockEnd: 18, regionStart: 10))
    }

    @Test func hunkBeforeBlockNoOverlap() {
        let hunk = makeHunk(newStart: 1, newLength: 2)
        #expect(!hunkOverlapsBlock(hunk, blockStart: 10, blockEnd: 20, regionStart: 1))
    }

    @Test func hunkAfterBlockNoOverlap() {
        let hunk = makeHunk(newStart: 30, newLength: 3)
        #expect(!hunkOverlapsBlock(hunk, blockStart: 5, blockEnd: 10, regionStart: 1))
    }

    @Test func hunkAdjacentWithinProximity() {
        let hunk = makeHunk(newStart: 14, newLength: 2)
        #expect(hunkOverlapsBlock(hunk, blockStart: 10, blockEnd: 12, regionStart: 1))
    }

    @Test func hunkJustOutsideProximity() {
        let hunk = makeHunk(newStart: 17, newLength: 2)
        #expect(!hunkOverlapsBlock(hunk, blockStart: 10, blockEnd: 12, regionStart: 1))
    }

    @Test func customProximity() {
        let hunk = makeHunk(newStart: 16, newLength: 1)
        #expect(hunkOverlapsBlock(hunk, blockStart: 10, blockEnd: 12, regionStart: 1, proximity: 5))
    }

    @Test func regionOffsetApplied() {
        let hunk = makeHunk(newStart: 5, newLength: 3)
        #expect(hunkOverlapsBlock(hunk, blockStart: 52, blockEnd: 58, regionStart: 50))
    }
}

@Suite struct TrimHunksTests {

    private func makeHunk(newStart: Int, newLength: Int) -> Hunk {
        Hunk(
            filePath: "test.py",
            content: "@@ -1,1 +\(newStart),\(newLength) @@\n+change",
            oldStart: 1,
            oldLength: 1,
            newStart: newStart,
            newLength: newLength
        )
    }

    @Test func keepsOverlappingHunks() {
        let overlapping = makeHunk(newStart: 6, newLength: 3)
        let result = trimHunks([overlapping], blockStart: 5, blockEnd: 10, regionStart: 1)
        #expect(result.count == 1)
    }

    @Test func removesDistantHunks() {
        let distant = makeHunk(newStart: 50, newLength: 3)
        let result = trimHunks([distant], blockStart: 5, blockEnd: 10, regionStart: 1)
        #expect(result.count == 0)
    }

    @Test func mixedKeepsAndRemoves() {
        let close = makeHunk(newStart: 6, newLength: 2)
        let far = makeHunk(newStart: 50, newLength: 2)
        let result = trimHunks([close, far], blockStart: 5, blockEnd: 10, regionStart: 1)
        #expect(result.count == 1)
        #expect(result[0].newStart == 6)
    }

    @Test func emptyInputReturnsEmpty() {
        let result = trimHunks([], blockStart: 5, blockEnd: 10, regionStart: 1)
        #expect(result == [])
    }
}

// MARK: - Tests: computeEffectiveDiffForCandidate

@Suite struct ComputeEffectiveDiffForCandidateTests {

    @Test func pureMoveProducesEmptyHunks() throws {
        let oldContent = "line1\nline2\nline3\nline4\nline5\n"
        let newContent = "line1\nline2\nline3\nline4\nline5\n"

        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [(1, "line1"), (2, "line2"), (3, "line3"), (4, "line4"), (5, "line5")],
            addedLines: [(1, "line1"), (2, "line2"), (3, "line3"), (4, "line4"), (5, "line5")]
        )

        let result = try computeEffectiveDiffForCandidate(
            candidate,
            oldFiles: ["old.py": oldContent],
            newFiles: ["new.py": newContent],
            contextLines: 2,
            rediff: gitRediff
        )
        #expect(result.hunks.count == 0)
        #expect(result.rawDiff == "")
    }

    @Test func moveWithChangeProducesDiff() throws {
        let oldContent = "def calc_total(items):\n    total = 0\n    for item in items:\n        total += item.price\n    return total\n"
        let newContent = "def calculate_total(items, tax=0):\n    total = 0\n    for item in items:\n        total += item.price\n    return total\n"

        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [(2, "    total = 0"), (3, "    for item in items:"), (4, "        total += item.price"), (5, "    return total")],
            addedLines: [(2, "    total = 0"), (3, "    for item in items:"), (4, "        total += item.price"), (5, "    return total")]
        )

        let result = try computeEffectiveDiffForCandidate(
            candidate,
            oldFiles: ["utils.py": oldContent],
            newFiles: ["helpers.py": newContent],
            contextLines: 2,
            rediff: gitRediff
        )
        #expect(result.hunks.count > 0)
        let hunkContent = result.hunks.map(\.content).joined(separator: "\n")
        #expect(hunkContent.contains("calc_total"))
        #expect(hunkContent.contains("calculate_total"))
    }

    @Test func resultReferencesOriginalCandidate() throws {
        let content = "line1\nline2\nline3\n"
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(1, "line1"), (2, "line2"), (3, "line3")],
            addedLines: [(1, "line1"), (2, "line2"), (3, "line3")]
        )
        let result = try computeEffectiveDiffForCandidate(
            candidate,
            oldFiles: ["a.py": content],
            newFiles: ["b.py": content],
            contextLines: 0,
            rediff: gitRediff
        )
        #expect(result.candidate == candidate)
    }
}
