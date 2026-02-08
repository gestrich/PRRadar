import Foundation
import Testing
@testable import PRRadarModels

@Suite("Hunk Behavior")
struct HunkBehaviorTests {

    static let sampleHunkContent = """
    diff --git a/main.swift b/main.swift
    index abc123..def456 100644
    --- a/main.swift
    +++ b/main.swift
    @@ -10,5 +10,7 @@ func existing() {
     // context line
    -    let old = 1
    +    let new = 2
    +    let extra = 3
     // more context
    """

    static var sampleHunk: Hunk {
        Hunk(
            filePath: "main.swift",
            content: sampleHunkContent,
            rawHeader: ["diff --git a/main.swift b/main.swift"],
            oldStart: 10,
            oldLength: 5,
            newStart: 10,
            newLength: 7
        )
    }

    // MARK: - getAnnotatedContent

    @Test("getAnnotatedContent adds line numbers to added and context lines")
    func annotatedContent() {
        let hunk = Self.sampleHunk
        let annotated = hunk.getAnnotatedContent()

        // Context lines get line numbers
        #expect(annotated.contains("  10:  // context line"))
        // Deleted lines get -
        #expect(annotated.contains("   -: -    let old = 1"))
        // Added lines get line numbers
        #expect(annotated.contains("  11: +    let new = 2"))
        #expect(annotated.contains("  12: +    let extra = 3"))
        // Context after additions
        #expect(annotated.contains("  13:  // more context"))
    }

    @Test("getAnnotatedContent preserves header lines as-is")
    func annotatedContentHeaders() {
        let hunk = Self.sampleHunk
        let annotated = hunk.getAnnotatedContent()

        #expect(annotated.contains("diff --git a/main.swift b/main.swift"))
        #expect(annotated.contains("--- a/main.swift"))
        #expect(annotated.contains("@@ -10,5 +10,7 @@"))
    }

    // MARK: - getDiffLines (structured)

    @Test("getDiffLines returns structured DiffLine objects with line numbers")
    func getDiffLinesStructured() {
        let hunk = Self.sampleHunk
        let lines = hunk.getDiffLines()

        // Should have header lines, context, removed, added lines
        let headers = lines.filter { $0.lineType == .header }
        let added = lines.filter { $0.lineType == .added }
        let removed = lines.filter { $0.lineType == .removed }
        let context = lines.filter { $0.lineType == .context }

        #expect(!headers.isEmpty)
        #expect(added.count == 2)
        #expect(removed.count == 1)
        #expect(context.count == 2)

        // Added lines have new line numbers
        #expect(added[0].newLineNumber == 11)
        #expect(added[1].newLineNumber == 12)
        #expect(added[0].oldLineNumber == nil)

        // Removed lines have old line numbers
        #expect(removed[0].oldLineNumber == 11)
        #expect(removed[0].newLineNumber == nil)

        // Context lines have both
        #expect(context[0].newLineNumber == 10)
        #expect(context[0].oldLineNumber == 10)
    }

    // MARK: - getAddedLines / getRemovedLines / getChangedLines

    @Test("getAddedLines returns only added lines")
    func getAddedLines() {
        let hunk = Self.sampleHunk
        let added = hunk.getAddedLines()
        #expect(added.count == 2)
        #expect(added.allSatisfy { $0.lineType == .added })
        #expect(added[0].content.contains("let new = 2"))
    }

    @Test("getRemovedLines returns only removed lines")
    func getRemovedLines() {
        let hunk = Self.sampleHunk
        let removed = hunk.getRemovedLines()
        #expect(removed.count == 1)
        #expect(removed[0].content.contains("let old = 1"))
    }

    @Test("getChangedLines returns both added and removed")
    func getChangedLines() {
        let hunk = Self.sampleHunk
        let changed = hunk.getChangedLines()
        #expect(changed.count == 3) // 1 removed + 2 added
        #expect(changed.allSatisfy { $0.isChanged })
    }

    @Test("getChangedContent returns concatenated changed text")
    func getChangedContent() {
        let hunk = Self.sampleHunk
        let text = hunk.getChangedContent()
        #expect(text.contains("let old = 1"))
        #expect(text.contains("let new = 2"))
        #expect(text.contains("let extra = 3"))
        #expect(!text.contains("context"))
    }

    // MARK: - extractChangedContent (static)

    @Test("extractChangedContent handles raw diff format")
    func extractChangedContentRaw() {
        let diffText = """
        @@ -1,3 +1,4 @@
         context
        -removed
        +added
        +new
        """

        let changed = Hunk.extractChangedContent(from: diffText)
        #expect(changed.contains("removed"))
        #expect(changed.contains("added"))
        #expect(changed.contains("new"))
        #expect(!changed.contains("context"))
    }

    @Test("extractChangedContent handles annotated diff format")
    func extractChangedContentAnnotated() {
        let diffText = """
        @@ -1,3 +1,4 @@
          10:  context
           -: -removed
          11: +added
        """

        let changed = Hunk.extractChangedContent(from: diffText)
        #expect(changed.contains("added"))
        #expect(changed.contains("removed"))
        #expect(!changed.contains("context"))
    }

    // MARK: - fromHunkData

    @Test("fromHunkData returns nil for empty file path")
    func fromHunkDataEmptyPath() {
        let result = Hunk.fromHunkData(fileHeader: [], hunkLines: ["@@ -1,3 +1,3 @@"], filePath: "")
        #expect(result == nil)
    }
}
