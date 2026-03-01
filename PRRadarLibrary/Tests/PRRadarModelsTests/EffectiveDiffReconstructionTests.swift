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

// MARK: - Tests: reconstructEffectiveDiff

@Suite struct ReconstructEffectiveDiffTests {

    /// Classify lines and group into hunks, then reconstruct — mirrors the pipeline flow.
    private func classifyAndReconstruct(
        originalDiff: GitDiff,
        effectiveResults: [EffectiveDiffResult]
    ) -> GitDiff {
        let classified = classifyLines(originalDiff: originalDiff, effectiveResults: effectiveResults)
        let hunks = groupIntoClassifiedHunks(originalDiff: originalDiff, classifiedLines: classified)
        return reconstructEffectiveDiff(originalDiff: originalDiff, classifiedHunks: hunks)
    }

    @Test func noMovesReturnsOriginal() {
        let diff = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 3),
                makeHunk("b.py", oldStart: 1, oldLength: 5, newStart: 1, newLength: 5),
            ],
            commitHash: ""
        )
        let result = classifyAndReconstruct(originalDiff: diff, effectiveResults: [])
        #expect(result.hunks.count == 2)
    }

    @Test func pureMoveFiltersAllMovedLines() {
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [(5, "a"), (6, "b"), (7, "c")],
            addedLines: [(10, "a"), (11, "b"), (12, "c")]
        )
        let effResult = makeEffectiveResult(candidate, hunks: [])

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("utils.py", oldStart: 5, oldLength: 3, newStart: 5, newLength: 0,
                         content: "@@ -5,3 +5,0 @@\n-a\n-b\n-c"),
                makeHunk("helpers.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 3,
                         content: "@@ -10,0 +10,3 @@\n+a\n+b\n+c"),
            ],
            commitHash: ""
        )
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [effResult])
        #expect(result.hunks.count == 0)
    }

    @Test func movePreservesNonMovedChangesInSourceHunk() {
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [(3, "moved1"), (4, "moved2")],
            addedLines: [(10, "moved1"), (11, "moved2")]
        )
        let effResult = makeEffectiveResult(candidate, hunks: [])

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("utils.py", oldStart: 1, oldLength: 5, newStart: 1, newLength: 0,
                         content: "@@ -1,5 +1,0 @@\n-genuine1\n-genuine2\n-moved1\n-moved2\n-genuine3"),
                makeHunk("helpers.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 2,
                         content: "@@ -10,0 +10,2 @@\n+moved1\n+moved2"),
                makeHunk("other.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 3,
                         content: "@@ -1,2 +1,3 @@\n-old\n+new\n+extra\n context"),
            ],
            commitHash: ""
        )
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [effResult])

        let utilsHunks = result.hunks.filter { $0.filePath == "utils.py" }
        #expect(utilsHunks.count == 2, "Non-moved removals should produce 2 sub-hunks (split at moved lines)")
        let allContent = utilsHunks.map(\.content).joined(separator: "\n")
        #expect(allContent.contains("-genuine1"))
        #expect(allContent.contains("-genuine2"))
        #expect(allContent.contains("-genuine3"))
        #expect(!allContent.contains("moved"))

        #expect(result.hunks.contains { $0.filePath == "other.py" })
    }

    @Test func movePreservesNewCodeInTargetHunk() {
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "handlers.py",
            removedLines: [(1, "calc"), (2, "total"), (3, "ret")],
            addedLines: [(4, "calc"), (5, "total"), (6, "ret")]
        )
        let effResult = makeEffectiveResult(candidate, hunks: [])

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("utils.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 0,
                         content: "@@ -1,3 +1,0 @@\n-calc\n-total\n-ret"),
                makeHunk("handlers.py", oldStart: 1, oldLength: 0, newStart: 1, newLength: 8,
                         content: "@@ -1,0 +1,8 @@\n+new_func1\n+new_body1\n+end1\n+calc\n+total\n+ret\n+new_func2\n+new_body2"),
            ],
            commitHash: ""
        )
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [effResult])

        let handlerHunks = result.hunks.filter { $0.filePath == "handlers.py" }
        #expect(handlerHunks.count == 2, "Non-moved additions should produce 2 sub-hunks")
        let allContent = handlerHunks.map(\.content).joined(separator: "\n")
        #expect(allContent.contains("+new_func1"))
        #expect(allContent.contains("+new_func2"))
        #expect(!allContent.contains("+calc"))
        #expect(!allContent.contains("+total"))
        #expect(!allContent.contains("+ret"))
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
                makeHunk("a.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 0,
                         content: "@@ -1,3 +1,0 @@\n-x\n-y\n-z"),
                makeHunk("b.py", oldStart: 1, oldLength: 0, newStart: 1, newLength: 3,
                         content: "@@ -1,0 +1,3 @@\n+x\n+y\n+z"),
                makeHunk("c.py", oldStart: 10, oldLength: 5, newStart: 10, newLength: 5),
                makeHunk("d.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 2),
            ],
            commitHash: ""
        )
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [effResult])
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
                makeHunk("a.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 0,
                         content: "@@ -1,3 +1,0 @@\n-x\n-y\n-z"),
                makeHunk("b.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 3,
                         content: "@@ -10,0 +10,3 @@\n+x\n+y\n+z"),
                makeHunk("c.py", oldStart: 5, oldLength: 3, newStart: 5, newLength: 0,
                         content: "@@ -5,3 +5,0 @@\n-p\n-q\n-r"),
                makeHunk("d.py", oldStart: 20, oldLength: 0, newStart: 20, newLength: 3,
                         content: "@@ -20,0 +20,3 @@\n+p\n+q\n+r"),
                makeHunk("keep.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 2),
            ],
            commitHash: ""
        )
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [eff1, eff2])
        #expect(result.hunks.count == 1)
        #expect(result.hunks[0].filePath == "keep.py")
    }

    @Test func preservesCommitHash() {
        let original = GitDiff(rawContent: "", hunks: [], commitHash: "abc123")
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [])
        #expect(result.commitHash == "abc123")
    }

    @Test func subHunksHaveCorrectLineNumbers() {
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [(3, "moved")],
            addedLines: [(3, "moved")]
        )
        let effResult = makeEffectiveResult(candidate)

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("utils.py", oldStart: 1, oldLength: 5, newStart: 1, newLength: 0,
                         content: "@@ -1,5 +1,0 @@\n-line1\n-line2\n-moved\n-line4\n-line5"),
            ],
            commitHash: ""
        )
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [effResult])

        #expect(result.hunks.count == 2)
        #expect(result.hunks[0].oldStart == 1)
        #expect(result.hunks[0].oldLength == 2)
        #expect(result.hunks[1].oldStart == 4)
        #expect(result.hunks[1].oldLength == 2)
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
