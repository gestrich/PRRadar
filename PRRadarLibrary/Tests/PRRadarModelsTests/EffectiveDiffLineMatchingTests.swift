import Testing
@testable import PRRadarModels

// MARK: - Helpers

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

private let whitespaceChangeRaw = """
diff --git a/utils.py b/utils.py
index aaa..bbb 100644
--- a/utils.py
+++ b/utils.py
@@ -1,3 +1,0 @@
-def save(data):
-    db.insert(data)
-    return True
diff --git a/models.py b/models.py
index ccc..ddd 100644
--- a/models.py
+++ b/models.py
@@ -0,0 +1,3 @@
+    def save(self, data):
+        db.insert(data)
+        return True
"""

private let duplicateLinesRaw = """
diff --git a/a.py b/a.py
index aaa..bbb 100644
--- a/a.py
+++ b/a.py
@@ -1,3 +1,0 @@
-    return None
-    return None
-    return None
diff --git a/b.py b/b.py
index ccc..ddd 100644
--- a/b.py
+++ b/b.py
@@ -0,0 +1,3 @@
+    return None
+    return None
+    return None
"""

private let blankLineRaw = """
diff --git a/a.py b/a.py
index aaa..bbb 100644
--- a/a.py
+++ b/a.py
@@ -1,3 +1,3 @@
-content_a
-
-content_b
+content_a
+
+content_b
"""

private let noMatchRaw = """
diff --git a/a.py b/a.py
index aaa..bbb 100644
--- a/a.py
+++ b/a.py
@@ -1,2 +1,2 @@
-old_function()
-old_helper()
+new_function()
+new_helper()
"""

private let multiHunkSameFileRaw = """
diff --git a/services.py b/services.py
index aaa..bbb 100644
--- a/services.py
+++ b/services.py
@@ -1,5 +1,0 @@
-def method_a():
-    return "a"
-
-def method_b():
-    return "b"
@@ -20,0 +15,5 @@
+def method_b():
+    return "b"
+
+def method_a():
+    return "a"
"""

// MARK: - Tests: extractTaggedLines

@Suite struct ExtractTaggedLinesTests {

    @Test func crossFileMoveExtractsRemovedAndAdded() {
        let gitDiff = makeDiff(crossFileMoveRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)

        #expect(removed.count == 5)
        #expect(added.count == 5)
        #expect(removed.allSatisfy { $0.filePath == "utils.py" })
        #expect(added.allSatisfy { $0.filePath == "helpers.py" })
    }

    @Test func taggedLineHasCorrectMetadata() {
        let gitDiff = makeDiff(crossFileMoveRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)

        let firstRemoved = removed[0]
        #expect(firstRemoved.content == "def calculate_total(items):")
        #expect(firstRemoved.normalized == "def calculate_total(items):")
        #expect(firstRemoved.filePath == "utils.py")
        #expect(firstRemoved.lineNumber == 1)
        #expect(firstRemoved.hunkIndex == 0)
        #expect(firstRemoved.lineType == .removed)

        let firstAdded = added[0]
        #expect(firstAdded.content == "def calculate_total(items):")
        #expect(firstAdded.filePath == "helpers.py")
        #expect(firstAdded.lineNumber == 1)
        #expect(firstAdded.hunkIndex == 1)
        #expect(firstAdded.lineType == .added)
    }

    @Test func sameHunkEditHasCorrectHunkIndex() {
        let gitDiff = makeDiff(sameHunkEditRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)

        #expect(removed.count == 1)
        #expect(added.count == 1)
        #expect(removed[0].hunkIndex == 0)
        #expect(added[0].hunkIndex == 0)
    }

    @Test func whitespaceNormalization() {
        let gitDiff = makeDiff(whitespaceChangeRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)

        let removedNorms = removed.map(\.normalized)
        let addedNorms = added.map(\.normalized)

        #expect(removedNorms.contains("db.insert(data)"))
        #expect(addedNorms.contains("db.insert(data)"))
        #expect(removedNorms.contains("return True"))
        #expect(addedNorms.contains("return True"))
    }

    @Test func contextLinesExcluded() {
        let gitDiff = makeDiff(sameHunkEditRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)

        let allContents = removed.map(\.content) + added.map(\.content)
        #expect(!allContents.contains("shared_line = True"))
    }

    @Test func multiHunkSameFileDifferentIndices() {
        let gitDiff = makeDiff(multiHunkSameFileRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)

        #expect(!removed.isEmpty)
        #expect(!added.isEmpty)
        #expect(removed[0].hunkIndex == 0)
        #expect(added[0].hunkIndex == 1)
    }
}

// MARK: - Tests: buildAddedIndex

@Suite struct BuildAddedIndexTests {

    @Test func indexKeysAreNormalized() {
        let gitDiff = makeDiff(whitespaceChangeRaw)
        let (_, added) = extractTaggedLines(from: gitDiff)
        let index = buildAddedIndex(added)

        #expect(index["db.insert(data)"] != nil)
        #expect(index["return True"] != nil)
    }

    @Test func blankLinesExcludedFromIndex() {
        let gitDiff = makeDiff(blankLineRaw)
        let (_, added) = extractTaggedLines(from: gitDiff)
        let index = buildAddedIndex(added)

        #expect(index[""] == nil)
    }

    @Test func duplicateLinesIndexedAsList() {
        let gitDiff = makeDiff(duplicateLinesRaw)
        let (_, added) = extractTaggedLines(from: gitDiff)
        let index = buildAddedIndex(added)

        #expect(index["return None"]?.count == 3)
    }
}

// MARK: - Tests: findExactMatches

@Suite struct FindExactMatchesTests {

    @Test func crossFilePureMoveAllLinesMatch() {
        let gitDiff = makeDiff(crossFileMoveRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        #expect(matches.count == 5)
        for m in matches {
            #expect(m.similarity == 1.0)
            #expect(m.removed.filePath == "utils.py")
            #expect(m.added.filePath == "helpers.py")
        }
    }

    @Test func crossFileDistanceIsPositive() {
        let gitDiff = makeDiff(crossFileMoveRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        for m in matches {
            #expect(m.distance == 1)
        }
    }

    @Test func sameHunkDistanceIsZero() {
        let gitDiff = makeDiff(sameHunkEditRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        #expect(matches.count == 0)
    }

    @Test func noMatchWhenContentDiffers() {
        let gitDiff = makeDiff(noMatchRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        #expect(matches.count == 0)
    }

    @Test func whitespaceNormalizedMatching() {
        let gitDiff = makeDiff(whitespaceChangeRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        let matchedNorms = Set(matches.map(\.removed.normalized))
        #expect(matchedNorms.contains("db.insert(data)"))
        #expect(matchedNorms.contains("return True"))
    }

    @Test func oneToOneMatching() {
        let gitDiff = makeDiff(duplicateLinesRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        #expect(matches.count == 3)
        let addedLineNumbers = matches.map(\.added.lineNumber)
        #expect(Set(addedLineNumbers).count == 3)
    }

    @Test func blankLinesNotMatched() {
        let gitDiff = makeDiff(blankLineRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        let matchedNorms = Set(matches.map(\.removed.normalized))
        #expect(!matchedNorms.contains(""))
    }

    @Test func multiHunkSwapMatches() {
        let gitDiff = makeDiff(multiHunkSameFileRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        #expect(matches.count == 4)
        for m in matches {
            #expect(m.distance > 0)
        }
    }

    @Test func matchPreservesOriginalContent() {
        let gitDiff = makeDiff(whitespaceChangeRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        let dbMatch = matches.first { $0.removed.normalized == "db.insert(data)" }!
        #expect(dbMatch.removed.content == "    db.insert(data)")
        #expect(dbMatch.added.content == "        db.insert(data)")
    }

    @Test func matchLineNumbersCorrect() {
        let gitDiff = makeDiff(crossFileMoveRaw)
        let (removed, added) = extractTaggedLines(from: gitDiff)
        let matches = findExactMatches(removedLines: removed, addedLines: added)

        let first = matches[0]
        #expect(first.removed.lineNumber == 1)
        #expect(first.added.lineNumber == 1)

        let last = matches[matches.count - 1]
        #expect(last.removed.lineNumber == 5)
        #expect(last.added.lineNumber == 5)
    }
}
