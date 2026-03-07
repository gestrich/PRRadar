import Foundation
import Testing
@testable import PRRadarModels

@Suite("PRMetadata")
struct PRMetadataTests {

    // MARK: - JSON Decoding

    @Test("decodes all fields including baseRefName")
    func decodesAllFields() throws {
        // Arrange
        let json = """
        {
            "number": 42,
            "title": "Add feature",
            "body": "Description here",
            "author": { "login": "octocat", "name": "Octo Cat" },
            "state": "OPEN",
            "headRefName": "feature/foo",
            "baseRefName": "main",
            "createdAt": "2025-01-15T00:00:00Z",
            "updatedAt": "2025-01-16T00:00:00Z",
            "url": "https://github.com/owner/repo/pull/42"
        }
        """.data(using: .utf8)!

        // Act
        let metadata = try JSONDecoder().decode(PRMetadata.self, from: json)

        // Assert
        #expect(metadata.number == 42)
        #expect(metadata.title == "Add feature")
        #expect(metadata.body == "Description here")
        #expect(metadata.author.login == "octocat")
        #expect(metadata.author.name == "Octo Cat")
        #expect(metadata.state == "OPEN")
        #expect(metadata.headRefName == "feature/foo")
        #expect(metadata.baseRefName == "main")
        #expect(metadata.createdAt == "2025-01-15T00:00:00Z")
        #expect(metadata.updatedAt == "2025-01-16T00:00:00Z")
        #expect(metadata.url == "https://github.com/owner/repo/pull/42")
    }

    @Test("round-trips through JSON encode/decode")
    func roundTrips() throws {
        // Arrange
        let original = PRMetadata(
            number: 7,
            title: "Fix bug",
            author: PRMetadata.Author(login: "dev", name: "Dev User"),
            state: "CLOSED",
            headRefName: "fix/bug",
            baseRefName: "develop",
            createdAt: "2025-02-01T10:00:00Z"
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PRMetadata.self, from: data)

        // Assert
        #expect(decoded.number == original.number)
        #expect(decoded.title == original.title)
        #expect(decoded.baseRefName == original.baseRefName)
        #expect(decoded.headRefName == original.headRefName)
        #expect(decoded.author.login == original.author.login)
    }

    @Test("missing baseRefName fails to decode")
    func missingBaseRefNameFailsDecode() {
        // Arrange
        let json = """
        {
            "number": 1,
            "title": "No base",
            "author": { "login": "a", "name": "A" },
            "state": "OPEN",
            "headRefName": "feature/x",
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        // Act & Assert
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PRMetadata.self, from: json)
        }
    }

    @Test("id is derived from number")
    func idFromNumber() {
        // Arrange
        let metadata = PRMetadata(
            number: 99,
            title: "Test",
            author: PRMetadata.Author(login: "u", name: "U"),
            state: "OPEN",
            headRefName: "h",
            baseRefName: "main",
            createdAt: "2025-01-01T00:00:00Z"
        )

        // Assert
        #expect(metadata.id == 99)
    }

    @Test("displayNumber formats with hash prefix")
    func displayNumber() {
        // Arrange
        let metadata = PRMetadata(
            number: 123,
            title: "Test",
            author: PRMetadata.Author(login: "u", name: "U"),
            state: "OPEN",
            headRefName: "h",
            baseRefName: "main",
            createdAt: "2025-01-01T00:00:00Z"
        )

        // Assert
        #expect(metadata.displayNumber == "#123")
    }

    @Test("fallback sets empty baseRefName")
    func fallbackMetadata() {
        // Act
        let metadata = PRMetadata.fallback(number: 5)

        // Assert
        #expect(metadata.number == 5)
        #expect(metadata.baseRefName == "")
        #expect(metadata.headRefName == "")
        #expect(metadata.author.login == "")
    }

    // MARK: - toPRMetadata conversion

    @Test("GitHubPullRequest converts to PRMetadata with baseRefName")
    func toPRMetadataIncludesBaseRefName() throws {
        // Arrange
        let pr = GitHubPullRequest(
            number: 10,
            title: "Feature",
            state: "open",
            baseRefName: "main",
            headRefName: "feature/x",
            createdAt: "2025-03-01T00:00:00Z",
            author: GitHubAuthor(login: "dev", name: "Dev")
        )

        // Act
        let metadata = try pr.toPRMetadata()

        // Assert
        #expect(metadata.baseRefName == "main")
        #expect(metadata.headRefName == "feature/x")
        #expect(metadata.author.login == "dev")
    }

    @Test("GitHubPullRequest without baseRefName throws")
    func toPRMetadataThrowsWithoutBaseRefName() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 10,
            title: "Feature",
            headRefName: "feature/x",
            createdAt: "2025-03-01T00:00:00Z",
            author: GitHubAuthor(login: "dev", name: "Dev")
        )

        // Act & Assert
        #expect(throws: PRMetadataConversionError.self) {
            try pr.toPRMetadata()
        }
    }

    @Test("GitHubPullRequest without author login throws")
    func toPRMetadataThrowsWithoutAuthorLogin() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 10,
            title: "Feature",
            baseRefName: "main",
            headRefName: "feature/x",
            createdAt: "2025-03-01T00:00:00Z"
        )

        // Act & Assert
        #expect(throws: PRMetadataConversionError.self) {
            try pr.toPRMetadata()
        }
    }
}
