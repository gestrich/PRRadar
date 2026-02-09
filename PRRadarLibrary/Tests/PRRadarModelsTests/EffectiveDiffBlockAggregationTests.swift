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

private func makeMatch(_ removed: TaggedLine, _ added: TaggedLine, distance: Int? = nil) -> LineMatch {
    let d = distance ?? abs(removed.hunkIndex - added.hunkIndex)
    return LineMatch(removed: removed, added: added, distance: d, similarity: 1.0)
}

private func makeDiff(_ raw: String) -> GitDiff {
    GitDiff.fromDiffContent(raw, commitHash: "")
}

// MARK: - Diff Fixtures

private let crossFileMoveRaw = """
diff --git a/utils.py b/utils.py
index aaa..bbb 100644
--- a/utils.py
+++ b/utils.py
@@ -1,5 +1,0 @@
-def calculate_total(items):
-    total = 0
-    for item in items:
-        total += item.price
-    return total
diff --git a/helpers.py b/helpers.py
index ccc..ddd 100644
--- a/helpers.py
+++ b/helpers.py
@@ -0,0 +1,5 @@
+def calculate_total(items):
+    total = 0
+    for item in items:
+        total += item.price
+    return total
"""

private let moveWithGapRaw = """
diff --git a/services.py b/services.py
index aaa..bbb 100644
--- a/services.py
+++ b/services.py
@@ -1,7 +1,0 @@
-def process_order(order):
-    validate(order)
-    total = sum(order.items)
-    tax = total * 0.08
-    order.total = total + tax
-    order.save()
-    return order
diff --git a/handlers.py b/handlers.py
index ccc..ddd 100644
--- a/handlers.py
+++ b/handlers.py
@@ -0,0 +1,7 @@
+def process_order(order):
+    validate(order)
+    total = sum(order.line_items)
+    tax = total * 0.08
+    order.total = total + tax
+    order.save()
+    return order
"""

private let sameHunkEditRaw = """
diff --git a/services.py b/services.py
index aaa..bbb 100644
--- a/services.py
+++ b/services.py
@@ -10,3 +10,3 @@ class Service:
-    x = old_value
+    x = new_value
     shared_line = True
"""

// MARK: - Tests: groupMatchesIntoBlocks

@Suite struct GroupMatchesIntoBlocksTests {

    @Test func consecutiveMatchesFormSingleBlock() {
        let removed = (1...5).map { makeRemoved("a.py", $0, "line \($0)") }
        let added = (1...5).map { makeAdded("b.py", $0, "line \($0)") }
        let matches = zip(removed, added).map { makeMatch($0, $1) }

        let blocks = groupMatchesIntoBlocks(matches)
        #expect(blocks.count == 1)
        #expect(blocks[0].count == 5)
    }

    @Test func smallGapAbsorbed() {
        let removed = [
            makeRemoved("a.py", 1, "line 1"),
            makeRemoved("a.py", 2, "line 2"),
            makeRemoved("a.py", 4, "line 4"),
            makeRemoved("a.py", 5, "line 5"),
        ]
        let added = [
            makeAdded("b.py", 1, "line 1"),
            makeAdded("b.py", 2, "line 2"),
            makeAdded("b.py", 4, "line 4"),
            makeAdded("b.py", 5, "line 5"),
        ]
        let matches = zip(removed, added).map { makeMatch($0, $1) }

        let blocks = groupMatchesIntoBlocks(matches)
        #expect(blocks.count == 1)
        #expect(blocks[0].count == 4)
    }

    @Test func gapAtToleranceLimitAbsorbed() {
        let removed = [
            makeRemoved("a.py", 1, "line 1"),
            makeRemoved("a.py", 5, "line 5"),
        ]
        let added = [
            makeAdded("b.py", 1, "line 1"),
            makeAdded("b.py", 5, "line 5"),
        ]
        let matches = zip(removed, added).map { makeMatch($0, $1) }

        let blocks = groupMatchesIntoBlocks(matches, gapTolerance: 3)
        #expect(blocks.count == 1)
    }

    @Test func gapExceedingToleranceSplitsBlock() {
        let removed = [
            makeRemoved("a.py", 1, "line 1"),
            makeRemoved("a.py", 2, "line 2"),
            makeRemoved("a.py", 7, "line 7"),
            makeRemoved("a.py", 8, "line 8"),
        ]
        let added = [
            makeAdded("b.py", 1, "line 1"),
            makeAdded("b.py", 2, "line 2"),
            makeAdded("b.py", 7, "line 7"),
            makeAdded("b.py", 8, "line 8"),
        ]
        let matches = zip(removed, added).map { makeMatch($0, $1) }

        let blocks = groupMatchesIntoBlocks(matches, gapTolerance: 3)
        #expect(blocks.count == 2)
        #expect(blocks[0].count == 2)
        #expect(blocks[1].count == 2)
    }

    @Test func distanceZeroFilteredOut() {
        let removed = (1...5).map { makeRemoved("a.py", $0, "line \($0)", hunkIndex: 0) }
        let added = (1...5).map { makeAdded("a.py", $0, "line \($0)", hunkIndex: 0) }
        let matches = zip(removed, added).map { makeMatch($0, $1, distance: 0) }

        let blocks = groupMatchesIntoBlocks(matches)
        #expect(blocks.count == 0)
    }

    @Test func differentFilePairsSeparateBlocks() {
        let r1 = (1...3).map { makeRemoved("a.py", $0, "line \($0)") }
        let a1 = (1...3).map { makeAdded("b.py", $0, "line \($0)") }
        let r2 = (1...3).map { makeRemoved("c.py", $0, "line \($0)") }
        let a2 = (1...3).map { makeAdded("d.py", $0, "line \($0)") }

        let matches = zip(r1, a1).map { makeMatch($0, $1) } + zip(r2, a2).map { makeMatch($0, $1) }

        let blocks = groupMatchesIntoBlocks(matches)
        #expect(blocks.count == 2)
    }

    @Test func emptyMatchesReturnsEmpty() {
        let blocks = groupMatchesIntoBlocks([])
        #expect(blocks.count == 0)
    }

    @Test func customGapTolerance() {
        let removed = [
            makeRemoved("a.py", 1, "line 1"),
            makeRemoved("a.py", 4, "line 4"),
        ]
        let added = [
            makeAdded("b.py", 1, "line 1"),
            makeAdded("b.py", 4, "line 4"),
        ]
        let matches = zip(removed, added).map { makeMatch($0, $1) }

        let blocks = groupMatchesIntoBlocks(matches, gapTolerance: 1)
        #expect(blocks.count == 2)
    }

    @Test func matchesSortedByRemovedLineNumber() {
        let removed = [
            makeRemoved("a.py", 5, "line 5"),
            makeRemoved("a.py", 3, "line 3"),
            makeRemoved("a.py", 1, "line 1"),
            makeRemoved("a.py", 4, "line 4"),
            makeRemoved("a.py", 2, "line 2"),
        ]
        let added = [
            makeAdded("b.py", 5, "line 5"),
            makeAdded("b.py", 3, "line 3"),
            makeAdded("b.py", 1, "line 1"),
            makeAdded("b.py", 4, "line 4"),
            makeAdded("b.py", 2, "line 2"),
        ]
        let matches = zip(removed, added).map { makeMatch($0, $1) }

        let blocks = groupMatchesIntoBlocks(matches)
        #expect(blocks.count == 1)
        #expect(blocks[0].count == 5)
        let lineNumbers = blocks[0].map(\.removed.lineNumber)
        #expect(lineNumbers == [1, 2, 3, 4, 5])
    }
}

// MARK: - Tests: findMoveCandidates

@Suite struct FindMoveCandidatesTests {

    @Test func crossFileMoveDetected() {
        let gitDiff = makeDiff(crossFileMoveRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        let candidates = findMoveCandidates(matches: matches, allAddedLines: added)
        #expect(candidates.count == 1)

        let c = candidates[0]
        #expect(c.sourceFile == "utils.py")
        #expect(c.targetFile == "helpers.py")
        #expect(c.sourceStartLine == 1)
        #expect(c.targetStartLine == 1)
        #expect(c.removedLines.count == 5)
        #expect(c.addedLines.count == 5)
        #expect(c.score > 0)
    }

    @Test func moveWithGapDetectedAsSingleBlock() {
        let gitDiff = makeDiff(moveWithGapRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        let candidates = findMoveCandidates(matches: matches, allAddedLines: added)
        #expect(candidates.count == 1)
        #expect(candidates[0].sourceFile == "services.py")
        #expect(candidates[0].targetFile == "handlers.py")
    }

    @Test func sameHunkEditNotDetectedAsMove() {
        let gitDiff = makeDiff(sameHunkEditRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        let candidates = findMoveCandidates(matches: matches, allAddedLines: added)
        #expect(candidates.count == 0)
    }

    @Test func smallBlockBelowThresholdExcluded() {
        let removed = [
            makeRemoved("a.py", 1, "line 1"),
            makeRemoved("a.py", 2, "line 2"),
        ]
        let added = [
            makeAdded("b.py", 1, "line 1"),
            makeAdded("b.py", 2, "line 2"),
        ]
        let matches = zip(removed, added).map { makeMatch($0, $1) }

        let candidates = findMoveCandidates(matches: matches, allAddedLines: added, minBlockSize: 3)
        #expect(candidates.count == 0)
    }

    @Test func candidatesSortedByScoreDescending() {
        let rLarge = (1...10).map { makeRemoved("a.py", $0, "unique_line_\($0)") }
        let aLarge = (1...10).map { makeAdded("b.py", $0, "unique_line_\($0)") }

        let rSmall = (1...3).map { makeRemoved("c.py", $0, "small_line_\($0)") }
        let aSmall = (1...3).map { makeAdded("d.py", $0, "small_line_\($0)") }

        let allAdded = aLarge + aSmall
        let matches = zip(rLarge, aLarge).map { makeMatch($0, $1) } + zip(rSmall, aSmall).map { makeMatch($0, $1) }

        let candidates = findMoveCandidates(matches: matches, allAddedLines: allAdded, minBlockSize: 3)
        #expect(candidates.count == 2)
        #expect(candidates[0].score >= candidates[1].score)
    }
}
