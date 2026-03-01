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

// MARK: - Tests: classifyLines

@Suite struct ClassifyLinesTests {

    @Test func genuinelyNewAddedLineClassifiedAsNew() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("app.py", oldStart: 1, oldLength: 0, newStart: 1, newLength: 2,
                         content: "@@ -1,0 +1,2 @@\n+brand_new_line\n+another_new")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Assert
        #expect(classified.count == 2)
        #expect(classified[0].classification == .new)
        #expect(classified[1].classification == .new)
        #expect(classified[0].content == "brand_new_line")
    }

    @Test func addedLinePartOfMoveClassifiedAsMoved() {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [(5, "moved_func"), (6, "body")],
            addedLines: [(10, "moved_func"), (11, "body")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("new.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 2,
                         content: "@@ -10,0 +10,2 @@\n+moved_func\n+body")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert
        #expect(classified.count == 2)
        #expect(classified[0].classification == .moved)
        #expect(classified[1].classification == .moved)
    }

    @Test func addedLineFromRediffClassifiedAsChangedInMove() {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [(1, "def calc():"), (2, "    return 0"), (3, "end")],
            addedLines: [(1, "def calc():"), (2, "    return 42"), (3, "end")]
        )
        let rediffHunk = makeHunk(
            "new.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 1,
            content: "@@ -1,1 +1,1 @@\n-    return 0\n+    return 42"
        )
        let effResult = makeEffectiveResult(candidate, hunks: [rediffHunk])
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("new.py", oldStart: 1, oldLength: 0, newStart: 1, newLength: 3,
                         content: "@@ -1,0 +1,3 @@\n+def calc():\n+    return 42\n+end")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert
        let changedInMove = classified.filter { $0.classification == .changedInMove }
        #expect(!changedInMove.isEmpty, "Re-diffed added line should be .changedInMove")
        let moved = classified.filter { $0.classification == .moved }
        #expect(!moved.isEmpty, "Unchanged moved lines should be .moved")
    }

    @Test func removedLinePartOfMoveClassifiedAsMovedRemoval() {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [(5, "func_a"), (6, "body_a")],
            addedLines: [(10, "func_a"), (11, "body_a")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("utils.py", oldStart: 5, oldLength: 2, newStart: 5, newLength: 0,
                         content: "@@ -5,2 +5,0 @@\n-func_a\n-body_a")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert
        #expect(classified.count == 2)
        #expect(classified[0].classification == .movedRemoval)
        #expect(classified[1].classification == .movedRemoval)
    }

    @Test func removedLineNotPartOfMoveClassifiedAsRemoved() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("app.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 0,
                         content: "@@ -1,2 +1,0 @@\n-deleted_line\n-also_deleted")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Assert
        #expect(classified.count == 2)
        #expect(classified[0].classification == .removed)
        #expect(classified[1].classification == .removed)
    }

    @Test func contextLineClassifiedAsContext() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("app.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 3,
                         content: "@@ -1,3 +1,3 @@\n context_line\n-old\n+new\n more_context")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Assert
        let contexts = classified.filter { $0.classification == .context }
        #expect(contexts.count == 2)
        #expect(contexts[0].content == "context_line")
        #expect(contexts[1].content == "more_context")
    }

    @Test func headerLinesAreSkipped() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("app.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 1,
                         content: "diff --git a/app.py b/app.py\n--- a/app.py\n+++ b/app.py\n@@ -1,1 +1,1 @@\n-old\n+new")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Assert
        #expect(classified.count == 2, "Headers should not produce classified lines")
        #expect(classified.allSatisfy { $0.lineType != .header })
    }

    @Test func preservesLineNumbers() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("app.py", oldStart: 10, oldLength: 2, newStart: 20, newLength: 2,
                         content: "@@ -10,2 +20,2 @@\n-old_line\n+new_line\n context")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Assert
        let removed = classified.first { $0.classification == .removed }
        #expect(removed?.oldLineNumber == 10)
        let added = classified.first { $0.classification == .new }
        #expect(added?.newLineNumber == 20)
    }

    @Test func preservesFilePath() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("src/main.swift", oldStart: 1, oldLength: 1, newStart: 1, newLength: 1,
                         content: "@@ -1,1 +1,1 @@\n-old\n+new")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Assert
        #expect(classified.allSatisfy { $0.filePath == "src/main.swift" })
    }

    @Test func mixedMovedAndNewInSameHunk() {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "handlers.py",
            removedLines: [(1, "moved_a"), (2, "moved_b")],
            addedLines: [(3, "moved_a"), (4, "moved_b")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("handlers.py", oldStart: 1, oldLength: 0, newStart: 1, newLength: 5,
                         content: "@@ -1,0 +1,5 @@\n+new_before\n+new_before2\n+moved_a\n+moved_b\n+new_after")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert
        #expect(classified[0].classification == .new, "Line before move should be .new")
        #expect(classified[1].classification == .new, "Line before move should be .new")
        #expect(classified[2].classification == .moved, "Moved line should be .moved")
        #expect(classified[3].classification == .moved, "Moved line should be .moved")
        #expect(classified[4].classification == .new, "Line after move should be .new")
    }
}

// MARK: - Tests: ClassifiedHunk derived properties

@Suite struct ClassifiedHunkPropertiesTests {

    private func makeLine(
        _ classification: LineClassification,
        lineType: DiffLineType = .added,
        content: String = "code"
    ) -> ClassifiedDiffLine {
        ClassifiedDiffLine(
            content: content,
            rawLine: lineType == .added ? "+\(content)" : lineType == .removed ? "-\(content)" : " \(content)",
            lineType: lineType,
            classification: classification,
            newLineNumber: lineType == .added || lineType == .context ? 1 : nil,
            oldLineNumber: lineType == .removed || lineType == .context ? 1 : nil,
            filePath: "test.py"
        )
    }

    @Test func isMovedTrueWhenAllNonContextLinesAreMoved() {
        // Arrange
        let hunk = ClassifiedHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(.context, lineType: .context),
            makeLine(.moved, lineType: .added),
            makeLine(.movedRemoval, lineType: .removed),
            makeLine(.context, lineType: .context),
        ])

        // Act & Assert
        #expect(hunk.isMoved)
    }

    @Test func isMovedFalseWhenNewCodePresent() {
        // Arrange
        let hunk = ClassifiedHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(.moved, lineType: .added),
            makeLine(.new, lineType: .added),
        ])

        // Act & Assert
        #expect(!hunk.isMoved)
    }

    @Test func isMovedFalseWhenAllContext() {
        // Arrange
        let hunk = ClassifiedHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(.context, lineType: .context),
        ])

        // Act & Assert
        #expect(!hunk.isMoved)
    }

    @Test func hasNewCodeDetectsNewLines() {
        // Arrange
        let hunk = ClassifiedHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(.context, lineType: .context),
            makeLine(.new, lineType: .added),
        ])

        // Act & Assert
        #expect(hunk.hasNewCode)
    }

    @Test func hasNewCodeFalseWhenNoNewLines() {
        // Arrange
        let hunk = ClassifiedHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(.moved, lineType: .added),
            makeLine(.context, lineType: .context),
        ])

        // Act & Assert
        #expect(!hunk.hasNewCode)
    }

    @Test func hasChangesInMoveDetectsChangedInMoveLines() {
        // Arrange
        let hunk = ClassifiedHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(.moved, lineType: .added),
            makeLine(.changedInMove, lineType: .added),
        ])

        // Act & Assert
        #expect(hunk.hasChangesInMove)
    }

    @Test func hasChangesInMoveFalseWhenNone() {
        // Arrange
        let hunk = ClassifiedHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(.moved, lineType: .added),
            makeLine(.new, lineType: .added),
        ])

        // Act & Assert
        #expect(!hunk.hasChangesInMove)
    }

    @Test func newCodeLinesReturnsOnlyNew() {
        // Arrange
        let hunk = ClassifiedHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(.new, lineType: .added, content: "genuinely_new"),
            makeLine(.moved, lineType: .added, content: "just_moved"),
            makeLine(.new, lineType: .added, content: "also_new"),
            makeLine(.context, lineType: .context, content: "ctx"),
        ])

        // Act
        let result = hunk.newCodeLines

        // Assert
        #expect(result.count == 2)
        #expect(result[0].content == "genuinely_new")
        #expect(result[1].content == "also_new")
    }

    @Test func changedLinesReturnsNewRemovedAndChangedInMove() {
        // Arrange
        let hunk = ClassifiedHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(.new, lineType: .added, content: "new_line"),
            makeLine(.removed, lineType: .removed, content: "deleted_line"),
            makeLine(.changedInMove, lineType: .added, content: "changed_in_move"),
            makeLine(.moved, lineType: .added, content: "just_moved"),
            makeLine(.movedRemoval, lineType: .removed, content: "source_of_move"),
            makeLine(.context, lineType: .context, content: "ctx"),
        ])

        // Act
        let result = hunk.changedLines

        // Assert
        #expect(result.count == 3)
        let contents = result.map(\.content)
        #expect(contents.contains("new_line"))
        #expect(contents.contains("deleted_line"))
        #expect(contents.contains("changed_in_move"))
    }
}

// MARK: - Tests: groupIntoClassifiedHunks

@Suite struct GroupIntoClassifiedHunksTests {

    @Test func groupsLinesIntoCorrectHunks() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 2,
                         content: "@@ -1,2 +1,2 @@\n-old\n+new\n ctx"),
                makeHunk("b.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 1,
                         content: "@@ -1,1 +1,1 @@\n-x\n+y"),
            ],
            commitHash: ""
        )
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Act
        let hunks = groupIntoClassifiedHunks(originalDiff: original, classifiedLines: classified)

        // Assert
        #expect(hunks.count == 2)
        #expect(hunks[0].filePath == "a.py")
        #expect(hunks[0].lines.count == 3)
        #expect(hunks[1].filePath == "b.py")
        #expect(hunks[1].lines.count == 2)
    }

    @Test func preservesHunkStartNumbers() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 10, oldLength: 1, newStart: 20, newLength: 1,
                         content: "@@ -10,1 +20,1 @@\n-old\n+new"),
            ],
            commitHash: ""
        )
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Act
        let hunks = groupIntoClassifiedHunks(originalDiff: original, classifiedLines: classified)

        // Assert
        #expect(hunks[0].oldStart == 10)
        #expect(hunks[0].newStart == 20)
    }
}

// MARK: - Tests: Moved method with interior change scenario

@Suite struct MovedMethodWithInteriorChangeTests {

    @Test func largeMethodMovedWithOneLineAdded() {
        // Arrange: a 5-line method moved from old.py to new.py, with one new line added in middle.
        // The inserted line shifts subsequent matched lines in the target.
        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [
                (1, "def process(data):"),
                (2, "    validate(data)"),
                (3, "    result = compute(data)"),
                (4, "    log(result)"),
                (5, "    return result"),
            ],
            addedLines: [
                (10, "def process(data):"),
                (11, "    validate(data)"),
                (12, "    result = compute(data)"),
                // line 13 = cache(result), the NEW line — not in candidate
                (14, "    log(result)"),
                (15, "    return result"),
            ]
        )
        // Re-diff hunk line numbers are relative to the extended block region.
        // extendBlockRange: target.start = max(1, 10-3) = 7
        // To map to absolute line 13: regionStart(7) + relativeLineNum(7) - 1 = 13
        let rediffHunk = makeHunk(
            "new.py", oldStart: 6, oldLength: 0, newStart: 7, newLength: 1,
            content: "@@ -6,0 +7,1 @@\n+    cache(result)"
        )
        let effResult = makeEffectiveResult(candidate, hunks: [rediffHunk])

        // Original diff: source side removes 5 lines, target side adds 6 lines (5 moved + 1 new)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("old.py", oldStart: 1, oldLength: 5, newStart: 1, newLength: 0,
                         content: "@@ -1,5 +1,0 @@\n-def process(data):\n-    validate(data)\n-    result = compute(data)\n-    log(result)\n-    return result"),
                makeHunk("new.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 6,
                         content: "@@ -10,0 +10,6 @@\n+def process(data):\n+    validate(data)\n+    result = compute(data)\n+    cache(result)\n+    log(result)\n+    return result"),
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert: source-side lines should all be .movedRemoval
        let sourceLines = classified.filter { $0.filePath == "old.py" }
        #expect(sourceLines.count == 5)
        #expect(sourceLines.allSatisfy { $0.classification == .movedRemoval })

        // Assert: target-side classification
        let targetLines = classified.filter { $0.filePath == "new.py" }
        #expect(targetLines.count == 6)

        // "cache(result)" at newLineNumber 13 should be .changedInMove
        let changedInMove = targetLines.filter { $0.classification == .changedInMove }
        #expect(!changedInMove.isEmpty, "The added line inside the moved block should be .changedInMove")
        #expect(changedInMove.contains { $0.content == "    cache(result)" })

        // The 5 matched lines should be .moved
        let moved = targetLines.filter { $0.classification == .moved }
        #expect(moved.count == 5, "Five original matched lines should be .moved")
    }

    @Test func movedMethodWithModifiedLine() {
        // Arrange: 4-line method moved, one line modified (old signature → new signature)
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "helpers.py",
            removedLines: [
                (1, "def calc(x):"),
                (2, "    total = 0"),
                (3, "    total += x"),
                (4, "    return total"),
            ],
            addedLines: [
                (5, "def calc(x):"),
                (6, "    total = 0"),
                (7, "    total += x"),
                (8, "    return total"),
            ]
        )
        // Re-diff: the first line changed (signature modification).
        // extendBlockRange: target.start = max(1, 5-3) = 2
        // To map to absolute line 5: regionStart(2) + relativeLineNum(4) - 1 = 5
        let rediffHunk = makeHunk(
            "helpers.py", oldStart: 4, oldLength: 1, newStart: 4, newLength: 1,
            content: "@@ -4,1 +4,1 @@\n-def calc(x):\n+def calculate(x, tax=0):"
        )
        let effResult = makeEffectiveResult(candidate, hunks: [rediffHunk])

        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("utils.py", oldStart: 1, oldLength: 4, newStart: 1, newLength: 0,
                         content: "@@ -1,4 +1,0 @@\n-def calc(x):\n-    total = 0\n-    total += x\n-    return total"),
                makeHunk("helpers.py", oldStart: 5, oldLength: 0, newStart: 5, newLength: 4,
                         content: "@@ -5,0 +5,4 @@\n+def calculate(x, tax=0):\n+    total = 0\n+    total += x\n+    return total"),
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert
        let targetLines = classified.filter { $0.filePath == "helpers.py" }
        let changedInMove = targetLines.filter { $0.classification == .changedInMove }
        #expect(changedInMove.count >= 1)
        #expect(changedInMove.contains { $0.content == "def calculate(x, tax=0):" })

        let moved = targetLines.filter { $0.classification == .moved }
        #expect(moved.count == 3)
    }
}

// MARK: - Tests: Classification → Reconstruction Equivalence

@Suite struct ClassificationReconstructionEquivalenceTests {

    private func classifyAndReconstruct(
        originalDiff: GitDiff,
        effectiveResults: [EffectiveDiffResult]
    ) -> GitDiff {
        let classified = classifyLines(originalDiff: originalDiff, effectiveResults: effectiveResults)
        let hunks = groupIntoClassifiedHunks(originalDiff: originalDiff, classifiedLines: classified)
        return reconstructEffectiveDiff(originalDiff: originalDiff, classifiedHunks: hunks)
    }

    @Test func noMovesPreservesAllHunks() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 2,
                         content: "@@ -1,2 +1,2 @@\n-old1\n+new1\n ctx"),
                makeHunk("b.py", oldStart: 5, oldLength: 1, newStart: 5, newLength: 2,
                         content: "@@ -5,1 +5,2 @@\n ctx\n+added"),
            ],
            commitHash: "abc"
        )

        // Act
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [])

        // Assert
        #expect(result.hunks.count == 2)
        #expect(result.commitHash == "abc")
    }

    @Test func pureMoveRemovesAllMovedHunks() {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(1, "x"), (2, "y"), (3, "z")],
            addedLines: [(10, "x"), (11, "y"), (12, "z")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 0,
                         content: "@@ -1,3 +1,0 @@\n-x\n-y\n-z"),
                makeHunk("b.py", oldStart: 10, oldLength: 0, newStart: 10, newLength: 3,
                         content: "@@ -10,0 +10,3 @@\n+x\n+y\n+z"),
            ],
            commitHash: ""
        )

        // Act
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [effResult])

        // Assert
        #expect(result.hunks.count == 0, "Pure move should produce empty effective diff")
    }

    @Test func movePreservesNonMovedCode() {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(2, "moved")],
            addedLines: [(5, "moved")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 0,
                         content: "@@ -1,3 +1,0 @@\n-genuine1\n-moved\n-genuine2"),
                makeHunk("b.py", oldStart: 5, oldLength: 0, newStart: 5, newLength: 1,
                         content: "@@ -5,0 +5,1 @@\n+moved"),
                makeHunk("c.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 2,
                         content: "@@ -1,1 +1,2 @@\n ctx\n+unrelated_new"),
            ],
            commitHash: ""
        )

        // Act
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [effResult])

        // Assert
        let allContent = result.hunks.map(\.content).joined(separator: "\n")
        #expect(allContent.contains("-genuine1"), "Non-moved removal should survive")
        #expect(allContent.contains("-genuine2"), "Non-moved removal should survive")
        #expect(!allContent.contains("moved"), "Moved line should be filtered out")
        #expect(result.hunks.contains { $0.filePath == "c.py" }, "Unrelated hunk should survive")
    }

    @Test func moveWithNewCodeAdjacentPreservesNewCode() {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "utils.py", targetFile: "handlers.py",
            removedLines: [(1, "moved1"), (2, "moved2")],
            addedLines: [(3, "moved1"), (4, "moved2")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("utils.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 0,
                         content: "@@ -1,2 +1,0 @@\n-moved1\n-moved2"),
                makeHunk("handlers.py", oldStart: 1, oldLength: 0, newStart: 1, newLength: 5,
                         content: "@@ -1,0 +1,5 @@\n+new_before\n+new_before2\n+moved1\n+moved2\n+new_after"),
            ],
            commitHash: ""
        )

        // Act
        let result = classifyAndReconstruct(originalDiff: original, effectiveResults: [effResult])

        // Assert
        let handlerHunks = result.hunks.filter { $0.filePath == "handlers.py" }
        #expect(handlerHunks.count >= 1, "New code should produce surviving hunks")
        let allContent = handlerHunks.map(\.content).joined(separator: "\n")
        #expect(allContent.contains("+new_before"), "New code before move should survive")
        #expect(allContent.contains("+new_after"), "New code after move should survive")
        #expect(!allContent.contains("+moved1"), "Moved lines should be filtered")
    }
}
