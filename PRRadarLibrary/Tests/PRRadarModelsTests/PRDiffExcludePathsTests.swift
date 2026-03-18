import Foundation
import Testing
@testable import PRRadarModels

@Suite("PRDiff.excludingPaths")
struct PRDiffExcludePathsTests {

    // MARK: - Helpers

    private func makeHunk(filePath: String) -> PRHunk {
        PRHunk(
            filePath: filePath,
            oldStart: 1,
            newStart: 1,
            lines: []
        )
    }

    private func makeDiff(filePaths: [String]) -> PRDiff {
        let hunks = filePaths.map { makeHunk(filePath: $0) }
        return PRDiff(
            commitHash: "abc123",
            rawText: "",
            hunks: hunks,
            moves: [],
            stats: DiffStats.compute(from: hunks)
        )
    }

    // MARK: - Tests

    @Test("Empty exclude patterns returns all hunks")
    func emptyPatterns() {
        let diff = makeDiff(filePaths: ["src/Main.swift", "Tests/MainTests.swift"])
        let filtered = diff.excludingPaths([])
        #expect(filtered.hunks.count == 2)
    }

    @Test("Excludes files matching wildcard pattern")
    func wildcardPattern() {
        let diff = makeDiff(filePaths: ["src/Main.swift", "src/Main.py", "src/Config.yaml"])
        let filtered = diff.excludingPaths(["*.py"])
        #expect(filtered.changedFiles == ["src/Config.yaml", "src/Main.swift"])
    }

    @Test("Excludes files matching substring pattern like *Tests* in filename")
    func substringPattern() {
        let diff = makeDiff(filePaths: [
            "Sources/App/Main.swift",
            "Tests/AppTests/MainTests.swift",
            "Sources/TestHelpers/Mock.swift",
        ])
        // *Tests* has no `/`, so it matches against filename only
        let filtered = diff.excludingPaths(["*Tests*"])
        #expect(filtered.changedFiles == ["Sources/App/Main.swift", "Sources/TestHelpers/Mock.swift"])
    }

    @Test("Excludes files matching path substring with **/pattern")
    func pathSubstringPattern() {
        let diff = makeDiff(filePaths: [
            "Sources/App/Main.swift",
            "Tests/AppTests/MainTests.swift",
            "Sources/TestHelpers/Mock.swift",
        ])
        // **/*Tests*/** matches paths containing Tests in any directory component
        let filtered = diff.excludingPaths(["**/Tests/**", "**/TestHelpers/**"])
        #expect(filtered.changedFiles == ["Sources/App/Main.swift"])
    }

    @Test("Excludes files matching path glob with **")
    func doubleWildcardPattern() {
        let diff = makeDiff(filePaths: [
            "src/app/Main.swift",
            "vendor/lib/Helper.swift",
            "vendor/other/Util.swift",
        ])
        let filtered = diff.excludingPaths(["vendor/**"])
        #expect(filtered.changedFiles == ["src/app/Main.swift"])
    }

    @Test("Multiple exclude patterns are combined")
    func multiplePatterns() {
        let diff = makeDiff(filePaths: [
            "src/Main.swift",
            "Tests/MainTests.swift",
            "docs/README.md",
        ])
        let filtered = diff.excludingPaths(["*Tests*", "*.md"])
        #expect(filtered.changedFiles == ["src/Main.swift"])
    }

    @Test("Non-matching patterns keep all hunks")
    func nonMatchingPattern() {
        let diff = makeDiff(filePaths: ["src/Main.swift", "src/Config.swift"])
        let filtered = diff.excludingPaths(["*.py"])
        #expect(filtered.hunks.count == 2)
    }

    @Test("Stats are recomputed after filtering")
    func statsRecomputed() {
        let diff = makeDiff(filePaths: ["src/Main.swift", "Tests/MainTests.swift"])
        let filtered = diff.excludingPaths(["*Tests*"])
        #expect(filtered.hunks.count == 1)
        #expect(filtered.changedFiles.count == 1)
    }
}
