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

private func makeHunk(
    _ filePath: String,
    oldStart: Int,
    oldLength: Int,
    newStart: Int,
    newLength: Int,
    content: String = ""
) -> Hunk {
    let c = content.isEmpty ? "@@ -\(oldStart),\(oldLength) +\(newStart),\(newLength) @@\n context" : content
    return Hunk(
        filePath: filePath,
        content: c,
        oldStart: oldStart,
        oldLength: oldLength,
        newStart: newStart,
        newLength: newLength
    )
}

private func makeEffectiveResult(
    _ candidate: MoveCandidate,
    hunks: [Hunk] = [],
    rawDiff: String = ""
) -> EffectiveDiffResult {
    EffectiveDiffResult(candidate: candidate, hunks: hunks, rawDiff: rawDiff)
}

// MARK: - Tests: hunkLineRange

@Suite struct HunkLineRangeTests {

    @Test func oldSideRange() {
        let hunk = makeHunk("a.py", oldStart: 10, oldLength: 5, newStart: 20, newLength: 5)
        let range = hunkLineRange(hunk, side: "old")
        #expect(range.start == 10)
        #expect(range.end == 14)
    }

    @Test func newSideRange() {
        let hunk = makeHunk("a.py", oldStart: 10, oldLength: 5, newStart: 20, newLength: 5)
        let range = hunkLineRange(hunk, side: "new")
        #expect(range.start == 20)
        #expect(range.end == 24)
    }

    @Test func zeroLengthOld() {
        let hunk = makeHunk("a.py", oldStart: 10, oldLength: 0, newStart: 20, newLength: 3)
        let range = hunkLineRange(hunk, side: "old")
        #expect(range.start == 10)
        #expect(range.end == 10)
    }

    @Test func singleLine() {
        let hunk = makeHunk("a.py", oldStart: 5, oldLength: 1, newStart: 5, newLength: 1)
        let range = hunkLineRange(hunk, side: "old")
        #expect(range.start == 5)
        #expect(range.end == 5)
    }
}

// MARK: - Tests: rangesOverlap

@Suite struct RangesOverlapTests {

    @Test func identicalRanges() {
        #expect(rangesOverlap(5, 10, 5, 10))
    }

    @Test func partialOverlap() {
        #expect(rangesOverlap(5, 10, 8, 15))
    }

    @Test func containment() {
        #expect(rangesOverlap(1, 20, 5, 10))
    }

    @Test func adjacentNoOverlap() {
        #expect(!rangesOverlap(5, 10, 11, 15))
    }

    @Test func distantNoOverlap() {
        #expect(!rangesOverlap(1, 5, 20, 30))
    }

    @Test func touchingBoundaries() {
        #expect(rangesOverlap(5, 10, 10, 15))
    }
}

// MARK: - Tests: classifyHunk

@Suite struct ClassifyHunkTests {

    private func setupMove() -> [EffectiveDiffResult] {
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [(5, "a"), (6, "b"), (7, "c"), (8, "d"), (9, "e"), (10, "f")],
            addedLines: [(15, "a"), (16, "b"), (17, "c"), (18, "d"), (19, "e"), (20, "f")]
        )
        return [makeEffectiveResult(candidate)]
    }

    @Test func hunkOnRemovedSide() {
        let results = setupMove()
        let hunk = makeHunk("utils.py", oldStart: 5, oldLength: 6, newStart: 5, newLength: 0)
        let classification = classifyHunk(hunk, effectiveResults: results)
        if case .moveRemoved = classification {} else {
            Issue.record("Expected moveRemoved")
        }
    }

    @Test func hunkOnAddedSide() {
        let results = setupMove()
        let hunk = makeHunk("helpers.py", oldStart: 15, oldLength: 0, newStart: 15, newLength: 6)
        let classification = classifyHunk(hunk, effectiveResults: results)
        if case .moveAdded = classification {} else {
            Issue.record("Expected moveAdded")
        }
    }

    @Test func hunkInDifferentFile() {
        let results = setupMove()
        let hunk = makeHunk("other.py", oldStart: 5, oldLength: 3, newStart: 5, newLength: 3)
        let classification = classifyHunk(hunk, effectiveResults: results)
        #expect(classification == .unchanged)
    }

    @Test func hunkInSourceFileButNoOverlap() {
        let results = setupMove()
        let hunk = makeHunk("utils.py", oldStart: 50, oldLength: 3, newStart: 50, newLength: 3)
        let classification = classifyHunk(hunk, effectiveResults: results)
        #expect(classification == .unchanged)
    }

    @Test func hunkInTargetFileButNoOverlap() {
        let results = setupMove()
        let hunk = makeHunk("helpers.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 3)
        let classification = classifyHunk(hunk, effectiveResults: results)
        #expect(classification == .unchanged)
    }

    @Test func noEffectiveResults() {
        let hunk = makeHunk("utils.py", oldStart: 5, oldLength: 3, newStart: 5, newLength: 3)
        let classification = classifyHunk(hunk, effectiveResults: [])
        #expect(classification == .unchanged)
    }
}

// MARK: - Tests: reconstructEffectiveDiff

@Suite struct ReconstructEffectiveDiffTests {

    @Test func noMovesReturnsOriginal() {
        let diff = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 3),
                makeHunk("b.py", oldStart: 1, oldLength: 5, newStart: 1, newLength: 5),
            ],
            commitHash: ""
        )
        let result = reconstructEffectiveDiff(originalDiff: diff, effectiveResults: [])
        #expect(result.hunks.count == 2)
    }

    @Test func pureMoveDropsBothSides() {
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [(5, "a"), (6, "b"), (7, "c")],
            addedLines: [(10, "a"), (11, "b"), (12, "c")]
        )
        let effResult = makeEffectiveResult(candidate, hunks: [])

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("utils.py", oldStart: 5, oldLength: 3, newStart: 5, newLength: 0),
                makeHunk("helpers.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 3),
            ],
            commitHash: ""
        )
        let result = reconstructEffectiveDiff(originalDiff: original, effectiveResults: [effResult])
        #expect(result.hunks.count == 0)
    }

    @Test func moveWithEffectiveDiffReplacesAddedSide() {
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [(5, "a"), (6, "b"), (7, "c")],
            addedLines: [(10, "a"), (11, "b"), (12, "c")]
        )
        let effectiveHunk = makeHunk(
            "helpers.py",
            oldStart: 1, oldLength: 1, newStart: 1, newLength: 1,
            content: "@@ -1,1 +1,1 @@\n-def old_sig():\n+def new_sig():"
        )
        let effResult = makeEffectiveResult(candidate, hunks: [effectiveHunk])

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("utils.py", oldStart: 5, oldLength: 3, newStart: 5, newLength: 0),
                makeHunk("helpers.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 3),
                makeHunk("other.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 3),
            ],
            commitHash: ""
        )
        let result = reconstructEffectiveDiff(originalDiff: original, effectiveResults: [effResult])
        #expect(result.hunks.count == 2)
        #expect(result.hunks[0].filePath == "helpers.py")
        #expect(result.hunks[0].content.contains("new_sig"))
        #expect(result.hunks[1].filePath == "other.py")
    }

    @Test func preservesUnrelatedHunks() {
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(1, "x"), (2, "y"), (3, "z")],
            addedLines: [(1, "x"), (2, "y"), (3, "z")]
        )
        let effResult = makeEffectiveResult(candidate)

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 0),
                makeHunk("b.py", oldStart: 1, oldLength: 0, newStart: 1, newLength: 3),
                makeHunk("c.py", oldStart: 10, oldLength: 5, newStart: 10, newLength: 5),
                makeHunk("d.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 2),
            ],
            commitHash: ""
        )
        let result = reconstructEffectiveDiff(originalDiff: original, effectiveResults: [effResult])
        #expect(result.hunks.count == 2)
        let filePaths = result.hunks.map(\.filePath)
        #expect(filePaths.contains("c.py"))
        #expect(filePaths.contains("d.py"))
    }

    @Test func multipleMoves() {
        let candidate1 = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(1, "x"), (2, "y"), (3, "z")],
            addedLines: [(10, "x"), (11, "y"), (12, "z")]
        )
        let candidate2 = makeCandidate(
            sourceFile: "c.py", targetFile: "d.py",
            removedLines: [(5, "p"), (6, "q"), (7, "r")],
            addedLines: [(20, "p"), (21, "q"), (22, "r")]
        )
        let eff1 = makeEffectiveResult(candidate1)
        let eff2 = makeEffectiveResult(candidate2)

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 0),
                makeHunk("b.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 3),
                makeHunk("c.py", oldStart: 5, oldLength: 3, newStart: 5, newLength: 0),
                makeHunk("d.py", oldStart: 20, oldLength: 0, newStart: 20, newLength: 3),
                makeHunk("keep.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 2),
            ],
            commitHash: ""
        )
        let result = reconstructEffectiveDiff(originalDiff: original, effectiveResults: [eff1, eff2])
        #expect(result.hunks.count == 1)
        #expect(result.hunks[0].filePath == "keep.py")
    }

    @Test func preservesCommitHash() {
        let original = GitDiff(rawContent: "", hunks: [], commitHash: "abc123")
        let result = reconstructEffectiveDiff(originalDiff: original, effectiveResults: [])
        #expect(result.commitHash == "abc123")
    }

    @Test func noDuplicateEffectiveHunks() {
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [(5, "a"), (6, "b"), (7, "c"), (8, "d"), (9, "e")],
            addedLines: [(10, "a"), (11, "b"), (12, "c"), (13, "d"), (14, "e")]
        )
        let effectiveHunk = makeHunk(
            "helpers.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 1,
            content: "@@ -1,1 +1,1 @@\n-old\n+new"
        )
        let effResult = makeEffectiveResult(candidate, hunks: [effectiveHunk])

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("helpers.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 3),
                makeHunk("helpers.py", oldStart: 13, oldLength: 0, newStart: 13, newLength: 2),
            ],
            commitHash: ""
        )
        let result = reconstructEffectiveDiff(originalDiff: original, effectiveResults: [effResult])
        #expect(result.hunks.count == 1)
        #expect(result.hunks[0].content.contains("new"))
    }
}

// MARK: - Tests: countChangedLinesInHunks

@Suite struct CountChangedLinesTests {

    @Test func countsAddedAndRemoved() {
        let hunk = makeHunk(
            "a.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 2,
            content: "@@ -1,2 +1,2 @@\n-old1\n-old2\n+new1\n+new2"
        )
        #expect(countChangedLinesInHunks([hunk]) == 4)
    }

    @Test func ignoresContextLines() {
        let hunk = makeHunk(
            "a.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 3,
            content: "@@ -1,3 +1,3 @@\n context\n-old\n+new\n context2"
        )
        #expect(countChangedLinesInHunks([hunk]) == 2)
    }

    @Test func emptyHunks() {
        #expect(countChangedLinesInHunks([]) == 0)
    }
}

// MARK: - Tests: buildMoveReport

@Suite struct BuildMoveReportTests {

    @Test func emptyResults() {
        let report = buildMoveReport([])
        #expect(report.movesDetected == 0)
        #expect(report.totalLinesMoved == 0)
        #expect(report.totalLinesEffectivelyChanged == 0)
        #expect(report.moves.count == 0)
    }

    @Test func singlePureMove() {
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(1, "x"), (2, "y"), (3, "z")],
            addedLines: [(10, "x"), (11, "y"), (12, "z")],
            score: 0.8
        )
        let effResult = makeEffectiveResult(candidate, hunks: [])

        let report = buildMoveReport([effResult])
        #expect(report.movesDetected == 1)
        #expect(report.totalLinesMoved == 3)
        #expect(report.totalLinesEffectivelyChanged == 0)
        #expect(report.moves[0].sourceFile == "a.py")
        #expect(report.moves[0].targetFile == "b.py")
        #expect(report.moves[0].sourceLines == (start: 1, end: 3))
        #expect(report.moves[0].targetLines == (start: 10, end: 12))
        #expect(report.moves[0].matchedLines == 3)
        #expect(report.moves[0].score == 0.8)
        #expect(report.moves[0].effectiveDiffLines == 0)
    }

    @Test func moveWithEffectiveChanges() {
        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [(5, "a"), (6, "b"), (7, "c"), (8, "d"), (9, "e")],
            addedLines: [(15, "a"), (16, "b"), (17, "c"), (18, "d"), (19, "e")]
        )
        let effectiveHunk = makeHunk(
            "new.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 1,
            content: "@@ -1,1 +1,1 @@\n-old_sig\n+new_sig"
        )
        let effResult = makeEffectiveResult(candidate, hunks: [effectiveHunk])

        let report = buildMoveReport([effResult])
        #expect(report.movesDetected == 1)
        #expect(report.totalLinesMoved == 5)
        #expect(report.totalLinesEffectivelyChanged == 2)
    }

    @Test func multipleMoves() {
        let c1 = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(1, "x"), (2, "y"), (3, "z")],
            addedLines: [(10, "x"), (11, "y"), (12, "z")]
        )
        let c2 = makeCandidate(
            sourceFile: "c.py", targetFile: "d.py",
            removedLines: [(1, "p"), (2, "q"), (3, "r"), (4, "s")],
            addedLines: [(20, "p"), (21, "q"), (22, "r"), (23, "s")]
        )
        let r1 = makeEffectiveResult(c1, hunks: [])
        let r2 = makeEffectiveResult(c2, hunks: [])

        let report = buildMoveReport([r1, r2])
        #expect(report.movesDetected == 2)
        #expect(report.totalLinesMoved == 7)
        #expect(report.moves.count == 2)
    }
}
