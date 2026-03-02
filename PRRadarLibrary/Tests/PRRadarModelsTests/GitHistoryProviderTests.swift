import CLISDK
import Foundation
import GitHubSDK
import GitSDK
import Testing
@testable import PRRadarCLIService
@testable import PRRadarConfigService
@testable import PRRadarModels

// MARK: - Mock GitHistoryProvider

struct MockGitHistoryProvider: GitHistoryProvider {
    var rawDiff: String = ""
    var fileContents: [String: String] = [:]  // keyed by "\(commit):\(filePath)"
    var mergeBaseResult: String = "abc123"
    var blobHashes: [String: String] = [:]  // keyed by "\(commit):\(filePath)"
    var errorToThrow: (any Error)?

    // Call tracking
    final class CallTracker: @unchecked Sendable {
        var getRawDiffCalls = 0
        var getFileContentCalls: [(commit: String, filePath: String)] = []
        var getMergeBaseCalls: [(commit1: String, commit2: String)] = []
        var getBlobHashCalls: [(commit: String, filePath: String)] = []

        func reset() {
            getRawDiffCalls = 0
            getFileContentCalls = []
            getMergeBaseCalls = []
            getBlobHashCalls = []
        }
    }

    let tracker = CallTracker()

    func getRawDiff() async throws -> String {
        tracker.getRawDiffCalls += 1
        if let error = errorToThrow { throw error }
        return rawDiff
    }

    func getFileContent(commit: String, filePath: String) async throws -> String {
        tracker.getFileContentCalls.append((commit, filePath))
        if let error = errorToThrow { throw error }
        let key = "\(commit):\(filePath)"
        guard let content = fileContents[key] else {
            throw MockError.fileNotFound(key)
        }
        return content
    }

    func getMergeBase(commit1: String, commit2: String) async throws -> String {
        tracker.getMergeBaseCalls.append((commit1, commit2))
        if let error = errorToThrow { throw error }
        return mergeBaseResult
    }

    func getBlobHash(commit: String, filePath: String) async throws -> String {
        tracker.getBlobHashCalls.append((commit, filePath))
        if let error = errorToThrow { throw error }
        let key = "\(commit):\(filePath)"
        guard let hash = blobHashes[key] else {
            throw MockError.hashNotFound(key)
        }
        return hash
    }

    enum MockError: Error {
        case fileNotFound(String)
        case hashNotFound(String)
    }
}

// MARK: - DiffSource Tests

@Suite("DiffSource")
struct DiffSourceTests {

    @Test("Raw values match expected CLI strings")
    func rawValues() {
        // Assert
        #expect(DiffSource.git.rawValue == "git")
        #expect(DiffSource.githubAPI.rawValue == "github-api")
    }

    @Test("Display names are human-readable")
    func displayNames() {
        // Assert
        #expect(DiffSource.git.displayName == "Local Git")
        #expect(DiffSource.githubAPI.displayName == "GitHub API")
    }

    @Test("CaseIterable includes both cases")
    func allCases() {
        // Assert
        #expect(DiffSource.allCases.count == 2)
        #expect(DiffSource.allCases.contains(.git))
        #expect(DiffSource.allCases.contains(.githubAPI))
    }

    @Test("JSON encodes to raw value string")
    func jsonEncoding() throws {
        // Act
        let gitData = try JSONEncoder().encode(DiffSource.git)
        let apiData = try JSONEncoder().encode(DiffSource.githubAPI)

        // Assert
        #expect(String(data: gitData, encoding: .utf8) == "\"git\"")
        #expect(String(data: apiData, encoding: .utf8) == "\"github-api\"")
    }

    @Test("JSON decodes from raw value string")
    func jsonDecoding() throws {
        // Arrange
        let gitJSON = Data("\"git\"".utf8)
        let apiJSON = Data("\"github-api\"".utf8)

        // Act
        let git = try JSONDecoder().decode(DiffSource.self, from: gitJSON)
        let api = try JSONDecoder().decode(DiffSource.self, from: apiJSON)

        // Assert
        #expect(git == .git)
        #expect(api == .githubAPI)
    }

    @Test("Decoding invalid raw value throws")
    func invalidRawValueThrows() {
        // Arrange
        let json = Data("\"invalid\"".utf8)

        // Act / Assert
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DiffSource.self, from: json)
        }
    }
}

// MARK: - TaskCreatorService Tests (with mock GitHistoryProvider)

@Suite("TaskCreatorService with GitHistoryProvider")
struct TaskCreatorServiceHistoryProviderTests {

    private func makeRule(name: String, focusType: FocusType = .file) -> ReviewRule {
        ReviewRule(
            name: name,
            filePath: "/rules/\(name).md",
            description: "Test rule",
            category: "test",
            focusType: focusType,
            content: "Rule content"
        )
    }

    private func makeFocusArea(filePath: String, focusType: FocusType = .file) -> FocusArea {
        FocusArea(
            focusId: "focus-\(filePath)",
            filePath: filePath,
            startLine: 1,
            endLine: 10,
            description: "Test focus",
            hunkIndex: 0,
            hunkContent: "@@ -1,5 +1,5 @@\n test content",
            focusType: focusType
        )
    }

    @Test("Uses historyProvider.getBlobHash for source file hashes")
    func usesBlobHashFromProvider() async throws {
        // Arrange
        var provider = MockGitHistoryProvider()
        provider.blobHashes["abc123:file.swift"] = "hash-abc"
        let gitOps = GitOperationsService(client: CLIClient())
        let ruleLoader = RuleLoaderService(gitOps: gitOps)
        let service = TaskCreatorService(ruleLoader: ruleLoader, gitOps: gitOps, historyProvider: provider)

        let rule = makeRule(name: "test-rule")
        let focusArea = makeFocusArea(filePath: "file.swift")

        // Act
        let tasks = try await service.createTasks(
            rules: [rule], focusAreas: [focusArea], commit: "abc123"
        )

        // Assert
        #expect(tasks.count == 1)
        #expect(tasks[0].gitBlobHash == "hash-abc")
        #expect(provider.tracker.getBlobHashCalls.count == 1)
        #expect(provider.tracker.getBlobHashCalls[0].commit == "abc123")
        #expect(provider.tracker.getBlobHashCalls[0].filePath == "file.swift")
    }

    @Test("Falls back to commit:filePath when getBlobHash throws")
    func fallbackOnBlobHashError() async throws {
        // Arrange
        let provider = MockGitHistoryProvider()
        // No blobHashes configured — will throw MockError.hashNotFound
        let gitOps = GitOperationsService(client: CLIClient())
        let ruleLoader = RuleLoaderService(gitOps: gitOps)
        let service = TaskCreatorService(ruleLoader: ruleLoader, gitOps: gitOps, historyProvider: provider)

        let rule = makeRule(name: "test-rule")
        let focusArea = makeFocusArea(filePath: "file.swift")

        // Act
        let tasks = try await service.createTasks(
            rules: [rule], focusAreas: [focusArea], commit: "abc123"
        )

        // Assert
        #expect(tasks.count == 1)
        #expect(tasks[0].gitBlobHash == "abc123:file.swift")
    }

    @Test("Caches blob hash across multiple focus areas for same file")
    func cachesBlobHashPerFile() async throws {
        // Arrange
        var provider = MockGitHistoryProvider()
        provider.blobHashes["abc123:file.swift"] = "hash-abc"
        let gitOps = GitOperationsService(client: CLIClient())
        let ruleLoader = RuleLoaderService(gitOps: gitOps)
        let service = TaskCreatorService(ruleLoader: ruleLoader, gitOps: gitOps, historyProvider: provider)

        let rule = makeRule(name: "test-rule")
        let focus1 = makeFocusArea(filePath: "file.swift")
        let focus2 = FocusArea(
            focusId: "focus-2",
            filePath: "file.swift",
            startLine: 11,
            endLine: 20,
            description: "Another focus",
            hunkIndex: 1,
            hunkContent: "@@ -11,5 +11,5 @@\n more content",
            focusType: .file
        )

        // Act
        _ = try await service.createTasks(
            rules: [rule], focusAreas: [focus1, focus2], commit: "abc123"
        )

        // Assert — getBlobHash called only once for the same file
        #expect(provider.tracker.getBlobHashCalls.count == 1)
    }

    @Test("Calls getBlobHash separately for different files")
    func separateBlobHashPerFile() async throws {
        // Arrange
        var provider = MockGitHistoryProvider()
        provider.blobHashes["abc123:file1.swift"] = "hash-1"
        provider.blobHashes["abc123:file2.swift"] = "hash-2"
        let gitOps = GitOperationsService(client: CLIClient())
        let ruleLoader = RuleLoaderService(gitOps: gitOps)
        let service = TaskCreatorService(ruleLoader: ruleLoader, gitOps: gitOps, historyProvider: provider)

        let rule = makeRule(name: "test-rule")
        let focus1 = makeFocusArea(filePath: "file1.swift")
        let focus2 = makeFocusArea(filePath: "file2.swift")

        // Act
        let tasks = try await service.createTasks(
            rules: [rule], focusAreas: [focus1, focus2], commit: "abc123"
        )

        // Assert
        #expect(tasks.count == 2)
        #expect(provider.tracker.getBlobHashCalls.count == 2)
        #expect(tasks[0].gitBlobHash == "hash-1")
        #expect(tasks[1].gitBlobHash == "hash-2")
    }
}

// MARK: - MockGitHistoryProvider Protocol Conformance Tests

@Suite("MockGitHistoryProvider")
struct MockGitHistoryProviderTests {

    @Test("getRawDiff returns configured value")
    func getRawDiff() async throws {
        // Arrange
        var provider = MockGitHistoryProvider()
        provider.rawDiff = "diff --git a/file.swift b/file.swift"

        // Act
        let result = try await provider.getRawDiff()

        // Assert
        #expect(result == "diff --git a/file.swift b/file.swift")
        #expect(provider.tracker.getRawDiffCalls == 1)
    }

    @Test("getFileContent returns content for known commit:path")
    func getFileContent() async throws {
        // Arrange
        var provider = MockGitHistoryProvider()
        provider.fileContents["abc123:file.swift"] = "let x = 1"

        // Act
        let result = try await provider.getFileContent(commit: "abc123", filePath: "file.swift")

        // Assert
        #expect(result == "let x = 1")
        #expect(provider.tracker.getFileContentCalls.count == 1)
    }

    @Test("getFileContent throws for unknown commit:path")
    func getFileContentThrows() async {
        // Arrange
        let provider = MockGitHistoryProvider()

        // Act / Assert
        await #expect(throws: MockGitHistoryProvider.MockError.self) {
            try await provider.getFileContent(commit: "abc123", filePath: "missing.swift")
        }
    }

    @Test("getMergeBase returns configured value and tracks call")
    func getMergeBase() async throws {
        // Arrange
        var provider = MockGitHistoryProvider()
        provider.mergeBaseResult = "merge-base-sha"

        // Act
        let result = try await provider.getMergeBase(commit1: "origin/main", commit2: "head-sha")

        // Assert
        #expect(result == "merge-base-sha")
        #expect(provider.tracker.getMergeBaseCalls.count == 1)
        #expect(provider.tracker.getMergeBaseCalls[0].commit1 == "origin/main")
        #expect(provider.tracker.getMergeBaseCalls[0].commit2 == "head-sha")
    }

    @Test("All methods throw when errorToThrow is set")
    func errorPropagation() async {
        // Arrange
        var provider = MockGitHistoryProvider()
        provider.errorToThrow = MockGitHistoryProvider.MockError.fileNotFound("forced")

        // Assert
        await #expect(throws: MockGitHistoryProvider.MockError.self) {
            try await provider.getRawDiff()
        }
        await #expect(throws: MockGitHistoryProvider.MockError.self) {
            try await provider.getFileContent(commit: "a", filePath: "b")
        }
        await #expect(throws: MockGitHistoryProvider.MockError.self) {
            try await provider.getMergeBase(commit1: "a", commit2: "b")
        }
        await #expect(throws: MockGitHistoryProvider.MockError.self) {
            try await provider.getBlobHash(commit: "a", filePath: "b")
        }
    }
}

// MARK: - GitHubServiceFactory.createHistoryProvider Tests

@Suite("GitHubServiceFactory.createHistoryProvider")
struct GitHistoryProviderFactoryTests {

    @Test("Returns LocalGitHistoryProvider for .git source")
    func gitSourceReturnsLocal() {
        // Arrange
        let gitOps = GitOperationsService(client: CLIClient())
        let octokitClient = OctokitClient(token: "fake-token")
        let gitHub = GitHubService(octokitClient: octokitClient, owner: "test", repo: "repo")

        // Act
        let provider = GitHubServiceFactory.createHistoryProvider(
            diffSource: .git,
            gitHub: gitHub,
            gitOps: gitOps,
            repoPath: "/tmp/repo",
            prNumber: 1,
            baseBranch: "main",
            headBranch: "feature"
        )

        // Assert
        #expect(provider is LocalGitHistoryProvider)
    }

    @Test("Returns GitHubAPIHistoryProvider for .githubAPI source")
    func githubAPISourceReturnsGitHub() {
        // Arrange
        let gitOps = GitOperationsService(client: CLIClient())
        let octokitClient = OctokitClient(token: "fake-token")
        let gitHub = GitHubService(octokitClient: octokitClient, owner: "test", repo: "repo")

        // Act
        let provider = GitHubServiceFactory.createHistoryProvider(
            diffSource: .githubAPI,
            gitHub: gitHub,
            gitOps: gitOps,
            repoPath: "/tmp/repo",
            prNumber: 1,
            baseBranch: "main",
            headBranch: "feature"
        )

        // Assert
        #expect(provider is GitHubAPIHistoryProvider)
    }
}
