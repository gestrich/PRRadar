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
    let ranges = extendBlockRange(candidate)
    let analysis = analyzeRediffHunks(hunks: hunks, targetFile: candidate.targetFile, sourceRegionStart: ranges.source.start, targetRegionStart: ranges.target.start)
    return EffectiveDiffResult(candidate: candidate, hunks: hunks, rawDiff: rawDiff, rediffAnalysis: analysis)
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
        #expect(classified[0].changeKind == .new)
        #expect(classified[1].changeKind == .new)
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
        #expect(classified[0].changeKind == .context && classified[0].move != nil)
        #expect(classified[1].changeKind == .context && classified[1].move != nil)
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
        let changedInMove = classified.filter { $0.changeKind.isReplacement && $0.move != nil }
        #expect(!changedInMove.isEmpty, "Re-diffed added line should be .replacement (changedInMove)")
        let moved = classified.filter { $0.changeKind == .context && $0.move != nil }
        #expect(!moved.isEmpty, "Unchanged moved lines should be .context (moved)")
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
        #expect(classified[0].move != nil)
        #expect(classified[1].move != nil)
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
        #expect(classified[0].changeKind == .deleted)
        #expect(classified[1].changeKind == .deleted)
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
        let contexts = classified.filter { $0.changeKind == .context }
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
        #expect(classified.allSatisfy { $0.diffType != .header })
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
        let removed = classified.first { $0.changeKind == .deleted }
        #expect(removed?.oldLineNumber == 10)
        let added = classified.first { $0.changeKind == .new }
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
        #expect(classified[0].changeKind == .new, "Line before move should be .new")
        #expect(classified[1].changeKind == .new, "Line before move should be .new")
        #expect(classified[2].changeKind == .context && classified[2].move != nil, "Moved line should be .context (moved)")
        #expect(classified[3].changeKind == .context && classified[3].move != nil, "Moved line should be .context (moved)")
        #expect(classified[4].changeKind == .new, "Line after move should be .new")
    }

    @Test func leadingWhitespaceOnlyChangeClassifiedAsUnchanged() {
        // Arrange — removed line has leading spaces, added line has none; content otherwise identical
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("file.swift", oldStart: 1, oldLength: 1, newStart: 1, newLength: 1,
                         content: "@@ -1,1 +1,1 @@\n-    foo()\n+foo()")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Assert — leading whitespace difference only → demoted to .context
        let added = classified.first { $0.diffType == .added }
        #expect(added?.changeKind == .context)
    }

    @Test func interiorWhitespaceChangeClassifiedAsAdded() {
        // Arrange — "* parentView" vs "*parentView": interior whitespace removed, not leading/trailing
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("file.h", oldStart: 1, oldLength: 1, newStart: 1, newLength: 1,
                         content: "@@ -1,1 +1,1 @@\n-@property (weak) RouteEditIPadView * parentView;\n+@property (weak) RouteEditIPadView *parentView;")
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Assert — interior whitespace difference → treated as real modification → .new (not .context)
        let added = classified.first { $0.diffType == .added }
        #expect(added?.changeKind == .new)
    }
}

// MARK: - Tests: PRHunk derived properties

@Suite struct PRHunkPropertiesTests {

    private static let testMoveInfo = MoveInfo(sourceFile: "old.py", targetFile: "new.py", isSource: false)

    private func makeLine(
        changeKind: ChangeKind,
        move: MoveInfo? = nil,
        lineType: DiffLineType = .added,
        content: String = "code"
    ) -> PRLine {
        PRLine(
            content: content,
            rawLine: lineType == .added ? "+\(content)" : lineType == .removed ? "-\(content)" : " \(content)",
            diffType: lineType,
            changeKind: changeKind,
            oldLineNumber: lineType == .removed || lineType == .context ? 1 : nil,
            newLineNumber: lineType == .added || lineType == .context ? 1 : nil,
            filePath: "test.py",
            move: move
        )
    }

    @Test func isMovedTrueWhenAllNonContextLinesAreMoved() {
        // Arrange
        let hunk = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .context, lineType: .context),
            makeLine(changeKind: .context, move: Self.testMoveInfo, lineType: .added),
            makeLine(changeKind: .context, move: Self.testMoveInfo, lineType: .removed),
            makeLine(changeKind: .context, lineType: .context),
        ])

        // Act & Assert
        #expect(hunk.isMoved)
    }

    @Test func isMovedFalseWhenNewCodePresent() {
        // Arrange
        let hunk = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .context, move: Self.testMoveInfo, lineType: .added),
            makeLine(changeKind: .new, lineType: .added),
        ])

        // Act & Assert
        #expect(!hunk.isMoved)
    }

    @Test func isMovedFalseWhenAllContext() {
        // Arrange
        let hunk = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .context, lineType: .context),
        ])

        // Act & Assert
        #expect(!hunk.isMoved)
    }

    @Test func hasNewCodeDetectsNewLines() {
        // Arrange
        let hunk = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .context, lineType: .context),
            makeLine(changeKind: .new, lineType: .added),
        ])

        // Act & Assert
        #expect(hunk.hasNewCode)
    }

    @Test func hasNewCodeFalseWhenNoNewLines() {
        // Arrange
        let hunk = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .context, move: Self.testMoveInfo, lineType: .added),
            makeLine(changeKind: .context, lineType: .context),
        ])

        // Act & Assert
        #expect(!hunk.hasNewCode)
    }

    @Test func hasChangesInMoveDetectsChangedInMoveLines() {
        // Arrange
        let hunk = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .context, move: Self.testMoveInfo, lineType: .added),
            makeLine(changeKind: .replacement(counterpart: Counterpart(filePath: "old.py", lineNumber: nil)), move: Self.testMoveInfo, lineType: .added),
        ])

        // Act & Assert
        #expect(hunk.hasChangesInMove)
    }

    @Test func hasChangesInMoveFalseWhenNone() {
        // Arrange
        let hunk = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .context, move: Self.testMoveInfo, lineType: .added),
            makeLine(changeKind: .new, lineType: .added),
        ])

        // Act & Assert
        #expect(!hunk.hasChangesInMove)
    }

    @Test func newCodeLinesReturnsOnlyNew() {
        // Arrange
        let hunk = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .new, lineType: .added, content: "genuinely_new"),
            makeLine(changeKind: .context, move: Self.testMoveInfo, lineType: .added, content: "just_moved"),
            makeLine(changeKind: .new, lineType: .added, content: "also_new"),
            makeLine(changeKind: .context, lineType: .context, content: "ctx"),
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
        let hunk = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .new, lineType: .added, content: "new_line"),
            makeLine(changeKind: .deleted, lineType: .removed, content: "deleted_line"),
            makeLine(changeKind: .replacement(counterpart: Counterpart(filePath: "old.py", lineNumber: nil)), move: Self.testMoveInfo, lineType: .added, content: "changed_in_move"),
            makeLine(changeKind: .context, move: Self.testMoveInfo, lineType: .added, content: "just_moved"),
            makeLine(changeKind: .context, move: Self.testMoveInfo, lineType: .removed, content: "source_of_move"),
            makeLine(changeKind: .context, lineType: .context, content: "ctx"),
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

// MARK: - Tests: groupIntoPRHunks

@Suite struct GroupIntoPRHunksTests {

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
        let hunks = groupIntoPRHunks(originalDiff: original, classifiedLines: classified)

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
        let hunks = groupIntoPRHunks(originalDiff: original, classifiedLines: classified)

        // Assert
        #expect(hunks[0].oldStart == 10)
        #expect(hunks[0].newStart == 20)
    }
}

// MARK: - Tests: Moved method with interior change scenario

@Suite struct MovedMethodWithInteriorChangeTests {

    @Test func largeMethodMovedWithOneLineAdded() {
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
                (14, "    log(result)"),
                (15, "    return result"),
            ]
        )
        let rediffHunk = makeHunk(
            "new.py", oldStart: 6, oldLength: 0, newStart: 7, newLength: 1,
            content: "@@ -6,0 +7,1 @@\n+    cache(result)"
        )
        let effResult = makeEffectiveResult(candidate, hunks: [rediffHunk])

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

        // Assert: source-side lines should all have move info
        let sourceLines = classified.filter { $0.filePath == "old.py" }
        #expect(sourceLines.count == 5)
        #expect(sourceLines.allSatisfy { $0.move != nil })

        // Assert: target-side classification
        let targetLines = classified.filter { $0.filePath == "new.py" }
        #expect(targetLines.count == 6)

        let addedInMove = targetLines.filter { $0.changeKind == .new && $0.move != nil }
        #expect(!addedInMove.isEmpty, "The inserted line inside the moved block should be .new + in move")
        #expect(addedInMove.contains { $0.content == "    cache(result)" })

        let moved = targetLines.filter { $0.changeKind == .context && $0.move != nil }
        #expect(moved.count == 5, "Five original matched lines should be .context (moved)")
    }

    @Test func movedMethodWithModifiedLine() {
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
        let changedInMove = targetLines.filter { $0.changeKind.isReplacement && $0.move != nil }
        #expect(changedInMove.count >= 1)
        #expect(changedInMove.contains { $0.content == "def calculate(x, tax=0):" })

        let moved = targetLines.filter { $0.changeKind == .context && $0.move != nil }
        #expect(moved.count == 3)
    }

    @Test func sourceLineModifiedAtDestinationClassifiedAsChanged() {
        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [(1, "line_a"), (2, "line_b"), (3, "line_c")],
            addedLines: [(10, "line_a"), (11, "line_b_modified"), (12, "line_c")]
        )
        let rediffHunk = makeHunk(
            "new.py", oldStart: 2, oldLength: 1, newStart: 2, newLength: 1,
            content: "@@ -2,1 +2,1 @@\n-line_b\n+line_b_modified"
        )
        let effResult = makeEffectiveResult(candidate, hunks: [rediffHunk])
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("old.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 0,
                         content: "@@ -1,3 +1,0 @@\n-line_a\n-line_b\n-line_c"),
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert
        let sourceLines = classified.filter { $0.filePath == "old.py" }
        #expect(sourceLines.count == 3)
        let changedSource = sourceLines.filter { $0.changeKind.isReplaced && $0.move != nil }
        #expect(changedSource.count == 1)
        #expect(changedSource[0].oldLineNumber == 2)

        let verbatim = sourceLines.filter { $0.changeKind == .context && $0.move != nil }
        #expect(verbatim.count == 2)
    }

    @Test func sourceLineDeletedFromMoveClassifiedAsRemoved() {
        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [(1, "line_a"), (2, "line_b"), (3, "line_c")],
            addedLines: [(10, "line_a"), (11, "line_c")]
        )
        let rediffHunk = makeHunk(
            "new.py", oldStart: 2, oldLength: 1, newStart: 2, newLength: 0,
            content: "@@ -2,1 +2,0 @@\n-line_b"
        )
        let effResult = makeEffectiveResult(candidate, hunks: [rediffHunk])
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("old.py", oldStart: 1, oldLength: 3, newStart: 1, newLength: 0,
                         content: "@@ -1,3 +1,0 @@\n-line_a\n-line_b\n-line_c"),
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert
        let sourceLines = classified.filter { $0.filePath == "old.py" }
        #expect(sourceLines.count == 3)
        let deletedFromMove = sourceLines.filter { $0.changeKind == .deleted && $0.move != nil }
        #expect(deletedFromMove.count == 1)
        #expect(deletedFromMove[0].oldLineNumber == 2)

        let verbatim = sourceLines.filter { $0.changeKind == .context && $0.move != nil }
        #expect(verbatim.count == 2)
    }

    @Test func verbatimMovedLinesAreUnchangedOnBothSides() {
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(5, "func_a"), (6, "body"), (7, "end")],
            addedLines: [(20, "func_a"), (21, "body"), (22, "end")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 5, oldLength: 3, newStart: 5, newLength: 0,
                         content: "@@ -5,3 +5,0 @@\n-func_a\n-body\n-end"),
                makeHunk("b.py", oldStart: 20, oldLength: 0, newStart: 20, newLength: 3,
                         content: "@@ -20,0 +20,3 @@\n+func_a\n+body\n+end"),
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert: source side
        let sourceLines = classified.filter { $0.filePath == "a.py" }
        #expect(sourceLines.count == 3)
        #expect(sourceLines.allSatisfy { $0.changeKind == .context && $0.move != nil })

        // Assert: target side
        let targetLines = classified.filter { $0.filePath == "b.py" }
        #expect(targetLines.count == 3)
        #expect(targetLines.allSatisfy { $0.changeKind == .context && $0.move != nil })
    }
}

// MARK: - Tests: PRDiff Codable

@Suite struct PRDiffCodableTests {

    @Test func codableRoundTrip() throws {
        // Arrange
        let prLine = PRLine(
            content: "new",
            rawLine: "+new",
            diffType: .added,
            changeKind: .new,
            oldLineNumber: nil,
            newLineNumber: 1,
            filePath: "test.py",
            move: nil
        )
        let prHunk = PRHunk(filePath: "test.py", oldStart: 1, newStart: 1, lines: [prLine])
        let prDiff = PRDiff(
            commitHash: "abc123",
            rawText: "raw",
            hunks: [prHunk],
            moves: [],
            stats: DiffStats(linesAdded: 1, linesRemoved: 0, linesMoved: 0, linesChanged: 0)
        )

        // Act
        let data = try JSONEncoder().encode(prDiff)
        let decoded = try JSONDecoder().decode(PRDiff.self, from: data)

        // Assert
        #expect(decoded.commitHash == "abc123")
        #expect(decoded.hunks.count == 1)
        #expect(decoded.hunks[0].lines[0].changeKind == .new)
        #expect(decoded.hunks[0].lines[0].move == nil)
    }
}

// MARK: - Tests: Classification → Reconstruction Equivalence

@Suite struct ClassificationReconstructionEquivalenceTests {

    private func classifyAndReconstruct(
        originalDiff: GitDiff,
        effectiveResults: [EffectiveDiffResult]
    ) -> GitDiff {
        let classified = classifyLines(originalDiff: originalDiff, effectiveResults: effectiveResults)
        let hunks = groupIntoPRHunks(originalDiff: originalDiff, classifiedLines: classified)
        return reconstructEffectiveDiff(originalDiff: originalDiff, prHunks: hunks)
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

// MARK: - Tests: MoveInfo population

@Suite struct MoveInfoPopulationTests {

    @Test func movedSourceLinesHaveCorrectMoveInfo() throws {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [(1, "func_a"), (2, "body_a")],
            addedLines: [(5, "func_a"), (6, "body_a")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("old.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 0,
                         content: "@@ -1,2 +1,0 @@\n-func_a\n-body_a"),
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert
        for line in classified {
            let info = try #require(line.move)
            #expect(info.sourceFile == "old.py")
            #expect(info.targetFile == "new.py")
            #expect(info.isSource == true)
        }
    }

    @Test func movedTargetLinesHaveCorrectMoveInfo() throws {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [(1, "func_a"), (2, "body_a")],
            addedLines: [(5, "func_a"), (6, "body_a")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("new.py", oldStart: 5, oldLength: 0, newStart: 5, newLength: 2,
                         content: "@@ -5,0 +5,2 @@\n+func_a\n+body_a"),
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [effResult])

        // Assert
        for line in classified {
            let info = try #require(line.move)
            #expect(info.sourceFile == "old.py")
            #expect(info.targetFile == "new.py")
            #expect(info.isSource == false)
        }
    }

    @Test func nonMovedLinesHaveNilMoveInfo() {
        // Arrange
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("app.py", oldStart: 1, oldLength: 0, newStart: 1, newLength: 1,
                         content: "@@ -1,0 +1,1 @@\n+new_line"),
            ],
            commitHash: ""
        )

        // Act
        let classified = classifyLines(originalDiff: original, effectiveResults: [])

        // Assert
        #expect(classified.count == 1)
        #expect(classified[0].move == nil)
    }
}

// MARK: - Tests: DiffStats.compute

@Suite struct DiffStatsComputeTests {

    private func makeLine(
        changeKind: ChangeKind,
        diffType: DiffLineType = .added,
        move: MoveInfo? = nil
    ) -> PRLine {
        PRLine(
            content: "x",
            rawLine: "+x",
            diffType: diffType,
            changeKind: changeKind,
            oldLineNumber: nil,
            newLineNumber: 1,
            filePath: "test.py",
            move: move
        )
    }

    @Test func countsAddedLines() {
        let hunks = [PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .new),
            makeLine(changeKind: .new),
        ])]

        let stats = DiffStats.compute(from: hunks)

        #expect(stats.linesAdded == 2)
        #expect(stats.linesRemoved == 0)
        #expect(stats.linesMoved == 0)
        #expect(stats.linesChanged == 0)
    }

    @Test func countsRemovedLines() {
        let hunks = [PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .deleted, diffType: .removed),
        ])]

        let stats = DiffStats.compute(from: hunks)

        #expect(stats.linesRemoved == 1)
    }

    @Test func countsMovedLines() {
        let moveInfo = MoveInfo(sourceFile: "a.py", targetFile: "b.py", isSource: false)
        let hunks = [PRHunk(filePath: "b.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .context, move: moveInfo),
            makeLine(changeKind: .context, move: moveInfo),
            makeLine(changeKind: .context, move: moveInfo),
        ])]

        let stats = DiffStats.compute(from: hunks)

        #expect(stats.linesMoved == 3)
        #expect(stats.linesAdded == 0)
    }

    @Test func countsChangedLines() {
        let moveInfo = MoveInfo(sourceFile: "a.py", targetFile: "b.py", isSource: false)
        let hunks = [PRHunk(filePath: "b.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .replacement(counterpart: Counterpart(filePath: "a.py", lineNumber: nil)), move: moveInfo),
        ])]

        let stats = DiffStats.compute(from: hunks)

        #expect(stats.linesChanged == 1)
    }

    @Test func ignoresContextLines() {
        let hunks = [PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .context, diffType: .context),
            makeLine(changeKind: .new),
        ])]

        let stats = DiffStats.compute(from: hunks)

        #expect(stats.linesAdded == 1)
        #expect(stats.linesMoved == 0)
    }

    @Test func mixedStats() {
        let moveInfo = MoveInfo(sourceFile: "a.py", targetFile: "b.py", isSource: false)
        let hunks = [PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [
            makeLine(changeKind: .new),
            makeLine(changeKind: .deleted, diffType: .removed),
            makeLine(changeKind: .context, move: moveInfo),
            makeLine(changeKind: .replacement(counterpart: Counterpart(filePath: "a.py", lineNumber: nil)), move: moveInfo),
            makeLine(changeKind: .context, diffType: .context),
        ])]

        let stats = DiffStats.compute(from: hunks)

        #expect(stats.linesAdded == 1)
        #expect(stats.linesRemoved == 1)
        #expect(stats.linesMoved == 1)
        #expect(stats.linesChanged == 1)
    }
}

// MARK: - Tests: PRDiff convenience methods

@Suite struct PRDiffConvenienceTests {

    private static let sampleDiff: PRDiff = {
        let line1 = PRLine(content: "new", rawLine: "+new", diffType: .added, changeKind: .new,
                           oldLineNumber: nil, newLineNumber: 1, filePath: "a.py", move: nil)
        let line2 = PRLine(content: "old", rawLine: "-old", diffType: .removed, changeKind: .deleted,
                           oldLineNumber: 1, newLineNumber: nil, filePath: "b.py", move: nil)
        let hunk1 = PRHunk(filePath: "a.py", oldStart: 1, newStart: 1, lines: [line1])
        let hunk2 = PRHunk(filePath: "b.py", oldStart: 1, newStart: 1, lines: [line2])
        return PRDiff(
            commitHash: "abc123",
            rawText: "",
            hunks: [hunk1, hunk2],
            moves: [],
            stats: DiffStats(linesAdded: 1, linesRemoved: 1, linesMoved: 0, linesChanged: 0)
        )
    }()

    @Test func changedFilesReturnsSortedUniqueFiles() {
        let files = Self.sampleDiff.changedFiles

        #expect(files == ["a.py", "b.py"])
    }

    @Test func hunksForFileFiltersCorrectly() {
        let hunks = Self.sampleDiff.hunks(forFile: "a.py")

        #expect(hunks.count == 1)
        #expect(hunks[0].filePath == "a.py")
    }

    @Test func hunksForFileReturnsEmptyForUnknownFile() {
        let hunks = Self.sampleDiff.hunks(forFile: "unknown.py")

        #expect(hunks.isEmpty)
    }

    @Test func fromRawDiffBuildsWithoutMoves() {
        // Arrange
        let gitDiff = GitDiff(
            rawContent: "raw",
            hunks: [
                makeHunk("file.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 2,
                         content: "@@ -1,1 +1,2 @@\n ctx\n+added")
            ],
            commitHash: "def456"
        )

        // Act
        let prDiff = PRDiff.fromRawDiff(gitDiff)

        // Assert
        #expect(prDiff.commitHash == "def456")
        #expect(prDiff.rawText == "raw")
        #expect(prDiff.hunks.count == 1)
        #expect(prDiff.moves.isEmpty)
        #expect(prDiff.stats.linesAdded == 1)
    }

    @Test func derivedMoveReportMatchesMoves() {
        // Arrange
        let move = MoveDetail(
            sourceFile: "a.py", targetFile: "b.py",
            sourceLines: [1, 2, 3, 4, 5], targetLines: [1, 2, 3, 4, 5],
            matchedLines: 5, score: 1.0, effectiveDiffLines: 0
        )
        let diff = PRDiff(
            commitHash: "abc",
            rawText: "",
            hunks: [],
            moves: [move],
            stats: DiffStats(linesAdded: 2, linesRemoved: 1, linesMoved: 5, linesChanged: 0)
        )

        // Act
        let report = diff.derivedMoveReport

        // Assert
        #expect(report.movesDetected == 1)
        #expect(report.totalLinesMoved == 5)
        #expect(report.totalLinesEffectivelyChanged == 3)
    }

    @Test func codableRoundTripWithMoveInfo() throws {
        // Arrange
        let moveInfo = MoveInfo(sourceFile: "old.py", targetFile: "new.py", isSource: false)
        let line = PRLine(content: "moved", rawLine: "+moved", diffType: .added, changeKind: .context,
                          oldLineNumber: nil, newLineNumber: 1, filePath: "new.py", move: moveInfo)
        let hunk = PRHunk(filePath: "new.py", oldStart: 1, newStart: 1, lines: [line])
        let move = MoveDetail(sourceFile: "old.py", targetFile: "new.py",
                              sourceLines: [1], targetLines: [1],
                              matchedLines: 1, score: 1.0, effectiveDiffLines: 0)
        let diff = PRDiff(
            commitHash: "abc",
            rawText: "raw",
            hunks: [hunk],
            moves: [move],
            stats: DiffStats(linesAdded: 0, linesRemoved: 0, linesMoved: 1, linesChanged: 0)
        )

        // Act
        let data = try JSONEncoder().encode(diff)
        let decoded = try JSONDecoder().decode(PRDiff.self, from: data)

        // Assert
        #expect(decoded.moves.count == 1)
        #expect(decoded.moves[0].sourceFile == "old.py")
        let decodedLine = try #require(decoded.hunks.first?.lines.first)
        let decodedMove = try #require(decodedLine.move)
        #expect(decodedMove.sourceFile == "old.py")
        #expect(decodedMove.targetFile == "new.py")
        #expect(decodedMove.isSource == false)
        #expect(decoded.stats.linesMoved == 1)
    }
}

// MARK: - Tests: PRDiff from pipeline output

@Suite struct PRDiffFromPipelineTests {

    @Test func pipelineProducesPRDiffWithCorrectStructure() {
        // Arrange: a simple diff with one added line, no moves
        let original = GitDiff(
            rawContent: "raw diff text",
            hunks: [
                makeHunk("app.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 2,
                         content: "@@ -1,1 +1,2 @@\n ctx\n+new_line"),
            ],
            commitHash: "abc123"
        )
        let classifiedLines = classifyLines(originalDiff: original, effectiveResults: [])
        let prHunks = groupIntoPRHunks(originalDiff: original, classifiedLines: classifiedLines)
        let stats = DiffStats.compute(from: prHunks)

        // Act
        let prDiff = PRDiff(
            commitHash: original.commitHash,
            rawText: original.rawContent,
            hunks: prHunks,
            moves: [],
            stats: stats
        )

        // Assert
        #expect(prDiff.commitHash == "abc123")
        #expect(prDiff.rawText == "raw diff text")
        #expect(prDiff.hunks.count == 1)
        #expect(prDiff.hunks[0].filePath == "app.py")
        #expect(prDiff.hunks[0].lines.count == 2)
        #expect(prDiff.moves.isEmpty)
        #expect(prDiff.stats.linesAdded == 1)
    }

    @Test func pipelineWithMovesPopulatesMoveInfoOnLines() {
        // Arrange
        let candidate = makeCandidate(
            sourceFile: "old.py", targetFile: "new.py",
            removedLines: [(1, "func_a"), (2, "body")],
            addedLines: [(5, "func_a"), (6, "body")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("old.py", oldStart: 1, oldLength: 2, newStart: 1, newLength: 0,
                         content: "@@ -1,2 +1,0 @@\n-func_a\n-body"),
                makeHunk("new.py", oldStart: 5, oldLength: 0, newStart: 5, newLength: 2,
                         content: "@@ -5,0 +5,2 @@\n+func_a\n+body"),
            ],
            commitHash: "def456"
        )
        let classifiedLines = classifyLines(originalDiff: original, effectiveResults: [effResult])
        let prHunks = groupIntoPRHunks(originalDiff: original, classifiedLines: classifiedLines)
        let stats = DiffStats.compute(from: prHunks)

        // Act
        let prDiff = PRDiff(
            commitHash: original.commitHash,
            rawText: original.rawContent,
            hunks: prHunks,
            moves: [],
            stats: stats
        )

        // Assert — source side
        let sourceHunk = prDiff.hunks(forFile: "old.py")
        #expect(sourceHunk.count == 1)
        for line in sourceHunk[0].lines {
            #expect(line.move?.isSource == true)
            #expect(line.move?.sourceFile == "old.py")
            #expect(line.move?.targetFile == "new.py")
        }

        // Assert — target side
        let targetHunk = prDiff.hunks(forFile: "new.py")
        #expect(targetHunk.count == 1)
        for line in targetHunk[0].lines {
            #expect(line.move?.isSource == false)
            #expect(line.move?.sourceFile == "old.py")
            #expect(line.move?.targetFile == "new.py")
        }

        // Assert — stats
        #expect(stats.linesMoved == 4)
        #expect(stats.linesAdded == 0)
    }

    @Test func pipelineStatsCountMixedChanges() {
        // Arrange: 1 genuine add, 2 moved, 1 context
        let candidate = makeCandidate(
            sourceFile: "a.py", targetFile: "b.py",
            removedLines: [(1, "moved")],
            addedLines: [(2, "moved")]
        )
        let effResult = makeEffectiveResult(candidate)
        let original = GitDiff(
            rawContent: "",
            hunks: [
                makeHunk("a.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 0,
                         content: "@@ -1,1 +1,0 @@\n-moved"),
                makeHunk("b.py", oldStart: 1, oldLength: 1, newStart: 1, newLength: 3,
                         content: "@@ -1,1 +1,3 @@\n ctx\n+moved\n+brand_new"),
            ],
            commitHash: ""
        )
        let classifiedLines = classifyLines(originalDiff: original, effectiveResults: [effResult])
        let prHunks = groupIntoPRHunks(originalDiff: original, classifiedLines: classifiedLines)

        // Act
        let stats = DiffStats.compute(from: prHunks)

        // Assert
        #expect(stats.linesMoved == 2)
        #expect(stats.linesAdded == 1)
        #expect(stats.linesRemoved == 0)
    }
}
