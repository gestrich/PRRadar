import Foundation
import Testing
@testable import PRRadarModels

@Suite("GitDiff Rename Parsing")
struct GitDiffRenameTests {

    // MARK: - Pure rename (100% similarity, no @@ hunks)

    @Test("Pure rename creates a Hunk with renameFrom set and empty diffLines")
    func pureRename() {
        let diff = """
        diff --git a/old/path.swift b/new/path.swift
        similarity index 100%
        rename from old/path.swift
        rename to new/path.swift
        """

        let gitDiff = GitDiff.fromDiffContent(diff, commitHash: "abc123")

        #expect(gitDiff.hunks.count == 1)
        let hunk = gitDiff.hunks[0]
        #expect(hunk.filePath == "new/path.swift")
        #expect(hunk.renameFrom == "old/path.swift")
        #expect(hunk.diffLines.isEmpty)
        #expect(hunk.oldStart == 0)
        #expect(hunk.oldLength == 0)
        #expect(hunk.newStart == 0)
        #expect(hunk.newLength == 0)
    }

    // MARK: - Rename with content changes

    @Test("Rename with changes has renameFrom set and populated diffLines")
    func renameWithChanges() {
        let diff = """
        diff --git a/old/path.swift b/new/path.swift
        similarity index 95%
        rename from old/path.swift
        rename to new/path.swift
        index abc123..def456 100644
        --- a/old/path.swift
        +++ b/new/path.swift
        @@ -1,3 +1,4 @@
         context line
        -old line
        +new line
        +added line
        """

        let gitDiff = GitDiff.fromDiffContent(diff, commitHash: "abc123")

        #expect(gitDiff.hunks.count == 1)
        let hunk = gitDiff.hunks[0]
        #expect(hunk.filePath == "new/path.swift")
        #expect(hunk.renameFrom == "old/path.swift")
        #expect(!hunk.diffLines.isEmpty)
        #expect(hunk.oldStart == 1)
        #expect(hunk.newStart == 1)
    }

    // MARK: - Mixed diff (renames + adds + modifies + deletes)

    @Test("Mixed diff with renames, additions, modifications, and deletions")
    func mixedDiff() {
        let diff = """
        diff --git a/added.swift b/added.swift
        new file mode 100644
        index 0000000..abc1234
        --- /dev/null
        +++ b/added.swift
        @@ -0,0 +1,3 @@
        +line 1
        +line 2
        +line 3
        diff --git a/old/moved.swift b/new/moved.swift
        similarity index 100%
        rename from old/moved.swift
        rename to new/moved.swift
        diff --git a/modified.swift b/modified.swift
        index abc123..def456 100644
        --- a/modified.swift
        +++ b/modified.swift
        @@ -1,3 +1,3 @@
         context
        -old
        +new
        diff --git a/deleted.swift b/deleted.swift
        deleted file mode 100644
        index abc1234..0000000
        --- a/deleted.swift
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -removed 1
        -removed 2
        """

        let gitDiff = GitDiff.fromDiffContent(diff, commitHash: "abc123")
        let files = gitDiff.changedFiles

        #expect(files.contains("added.swift"))
        #expect(files.contains("new/moved.swift"))
        #expect(files.contains("modified.swift"))
        #expect(files.contains("deleted.swift"))
        #expect(files.count == 4)
    }

    // MARK: - renamedFiles convenience

    @Test("renamedFiles returns correct from/to pairs")
    func renamedFilesConvenience() {
        let diff = """
        diff --git a/a.swift b/b.swift
        similarity index 100%
        rename from a.swift
        rename to b.swift
        diff --git a/normal.swift b/normal.swift
        index abc123..def456 100644
        --- a/normal.swift
        +++ b/normal.swift
        @@ -1,3 +1,3 @@
         context
        -old
        +new
        diff --git a/x/old.swift b/y/new.swift
        similarity index 90%
        rename from x/old.swift
        rename to y/new.swift
        index abc123..def456 100644
        --- a/x/old.swift
        +++ b/y/new.swift
        @@ -1,2 +1,3 @@
         keep
        +added
        """

        let gitDiff = GitDiff.fromDiffContent(diff, commitHash: "abc123")
        let renames = gitDiff.renamedFiles

        #expect(renames.count == 2)

        let sorted = renames.sorted { $0.from < $1.from }
        #expect(sorted[0].from == "a.swift")
        #expect(sorted[0].to == "b.swift")
        #expect(sorted[1].from == "x/old.swift")
        #expect(sorted[1].to == "y/new.swift")
    }

    // MARK: - Non-rename diffs unchanged

    @Test("Normal diffs without renames have nil renameFrom")
    func nonRenameDiffUnchanged() {
        let diff = """
        diff --git a/file.swift b/file.swift
        index abc123..def456 100644
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,4 @@
         context
        -old
        +new
        +extra
        """

        let gitDiff = GitDiff.fromDiffContent(diff, commitHash: "abc123")

        #expect(gitDiff.hunks.count == 1)
        #expect(gitDiff.hunks[0].renameFrom == nil)
        #expect(gitDiff.renamedFiles.isEmpty)
        #expect(!gitDiff.hunks[0].diffLines.isEmpty)
    }

    // MARK: - Codable round-trip with renameFrom

    @Test("Hunk with renameFrom round-trips through encode/decode")
    func renameFromCodableRoundTrip() throws {
        let hunk = Hunk(
            filePath: "new/path.swift",
            content: "diff --git a/old/path.swift b/new/path.swift",
            rawHeader: ["diff --git a/old/path.swift b/new/path.swift"],
            renameFrom: "old/path.swift"
        )

        let encoded = try JSONEncoder().encode(hunk)
        let decoded = try JSONDecoder().decode(Hunk.self, from: encoded)

        #expect(decoded.filePath == "new/path.swift")
        #expect(decoded.renameFrom == "old/path.swift")
    }

    @Test("Hunk without renameFrom decodes with nil renameFrom")
    func noRenameFromCodableRoundTrip() throws {
        let hunk = Hunk(
            filePath: "file.swift",
            content: "@@ -1,3 +1,3 @@\n context\n-old\n+new",
            rawHeader: ["diff --git a/file.swift b/file.swift"]
        )

        let encoded = try JSONEncoder().encode(hunk)
        let decoded = try JSONDecoder().decode(Hunk.self, from: encoded)

        #expect(decoded.filePath == "file.swift")
        #expect(decoded.renameFrom == nil)
    }

    // MARK: - Backward compatibility: decode old JSON without renameFrom

    @Test("Decoding JSON without renameFrom field defaults to nil")
    func backwardCompatibleDecode() throws {
        let json = """
        {
            "filePath": "test.swift",
            "content": "some content",
            "rawHeader": [],
            "oldStart": 1,
            "oldLength": 3,
            "newStart": 1,
            "newLength": 4
        }
        """.data(using: .utf8)!

        let hunk = try JSONDecoder().decode(Hunk.self, from: json)
        #expect(hunk.renameFrom == nil)
        #expect(hunk.filePath == "test.swift")
    }
}
