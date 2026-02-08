import Foundation
import Testing
@testable import PRRadarModels

@Suite("FocusArea Behavior")
struct FocusAreaBehaviorTests {

    // MARK: - Memberwise Init

    @Test("FocusArea memberwise init sets all fields")
    func focusAreaInit() {
        let area = FocusArea(
            focusId: "method-main-foo-10-20",
            filePath: "main.swift",
            startLine: 10,
            endLine: 20,
            description: "foo method",
            hunkIndex: 0,
            hunkContent: "@@ -10,5 +10,8 @@\n  10: +func foo() {",
            focusType: .method
        )

        #expect(area.focusId == "method-main-foo-10-20")
        #expect(area.filePath == "main.swift")
        #expect(area.startLine == 10)
        #expect(area.endLine == 20)
        #expect(area.focusType == .method)
    }

    @Test("FocusArea default focusType is .file")
    func focusAreaDefaultType() {
        let area = FocusArea(
            focusId: "test",
            filePath: "test.swift",
            startLine: 1,
            endLine: 10,
            description: "test",
            hunkIndex: 0,
            hunkContent: ""
        )
        #expect(area.focusType == .file)
    }

    // MARK: - getFocusedContent

    @Test("getFocusedContent extracts lines within focus bounds")
    func getFocusedContent() {
        let hunkContent = """
        @@ -10,5 +10,8 @@
          10: +func foo() {
          11: +    let x = 1
          12: +    let y = 2
          13: +    return x + y
          14: +}
          15:  // other code
        """

        let area = FocusArea(
            focusId: "test",
            filePath: "main.swift",
            startLine: 10,
            endLine: 13,
            description: "test",
            hunkIndex: 0,
            hunkContent: hunkContent
        )

        let focused = area.getFocusedContent()
        #expect(focused.contains("@@ -10,5 +10,8 @@"))
        #expect(focused.contains("func foo()"))
        #expect(focused.contains("return x + y"))
        #expect(!focused.contains("other code"))
    }

    @Test("getFocusedContent skips lines without line numbers")
    func getFocusedContentSkipsNonAnnotated() {
        let hunkContent = """
        @@ -1,3 +1,5 @@
           -: -old line
           1: +new line
           2:  context
        """

        let area = FocusArea(
            focusId: "test",
            filePath: "test.swift",
            startLine: 1,
            endLine: 2,
            description: "test",
            hunkIndex: 0,
            hunkContent: hunkContent
        )

        let focused = area.getFocusedContent()
        #expect(focused.contains("new line"))
        #expect(focused.contains("context"))
    }

    // MARK: - getContextAroundLine

    @Test("getContextAroundLine returns context centered on target line")
    func getContextAroundLine() {
        let hunkContent = """
        @@ -1,8 +1,8 @@
           1: +line one
           2: +line two
           3: +line three
           4: +line four
           5: +line five
        """

        let area = FocusArea(
            focusId: "test",
            filePath: "test.swift",
            startLine: 1,
            endLine: 5,
            description: "test",
            hunkIndex: 0,
            hunkContent: hunkContent
        )

        let context = area.getContextAroundLine(3, contextLines: 1)
        #expect(context.contains("line two"))
        #expect(context.contains("line three"))
        #expect(context.contains("line four"))
    }

    @Test("getContextAroundLine with nil returns first few lines")
    func getContextAroundLineNil() {
        let hunkContent = """
        @@ -1,3 +1,3 @@
           1: +line one
           2: +line two
        """

        let area = FocusArea(
            focusId: "test",
            filePath: "test.swift",
            startLine: 1,
            endLine: 2,
            description: "test",
            hunkIndex: 0,
            hunkContent: hunkContent
        )

        let context = area.getContextAroundLine(nil, contextLines: 1)
        #expect(context.contains("@@"))
    }

    // MARK: - contentHash

    @Test("contentHash returns 8-character hex string")
    func contentHashFormat() {
        let area = FocusArea(
            focusId: "test",
            filePath: "test.swift",
            startLine: 1,
            endLine: 10,
            description: "test",
            hunkIndex: 0,
            hunkContent: "some content here"
        )

        let hash = area.contentHash()
        #expect(hash.count == 8)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test("contentHash is deterministic")
    func contentHashDeterministic() {
        let area1 = FocusArea(
            focusId: "a", filePath: "a", startLine: 1, endLine: 1,
            description: "a", hunkIndex: 0, hunkContent: "same content"
        )
        let area2 = FocusArea(
            focusId: "b", filePath: "b", startLine: 2, endLine: 2,
            description: "b", hunkIndex: 1, hunkContent: "same content"
        )
        #expect(area1.contentHash() == area2.contentHash())
    }

    @Test("contentHash differs for different content")
    func contentHashDiffers() {
        let area1 = FocusArea(
            focusId: "a", filePath: "a", startLine: 1, endLine: 1,
            description: "a", hunkIndex: 0, hunkContent: "content A"
        )
        let area2 = FocusArea(
            focusId: "a", filePath: "a", startLine: 1, endLine: 1,
            description: "a", hunkIndex: 0, hunkContent: "content B"
        )
        #expect(area1.contentHash() != area2.contentHash())
    }
}
