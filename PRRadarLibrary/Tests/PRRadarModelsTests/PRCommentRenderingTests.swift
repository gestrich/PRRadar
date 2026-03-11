import Testing
@testable import PRRadarModels

@Suite("PRComment rendering and metadata")
struct PRCommentRenderingTests {

    private func makeComment(
        ruleName: String = "no-force-unwrap",
        score: Int = 7,
        comment: String = "Avoid force unwraps",
        filePath: String = "Sources/App.swift",
        lineNumber: Int? = 42,
        ruleUrl: String? = nil,
        relevantClaudeSkill: String? = nil,
        documentationLink: String? = nil,
        analysisMethod: AnalysisMethod? = nil,
        ruleHash: String = "abc123",
        fileBlobSHA: String? = nil
    ) -> PRComment {
        PRComment(
            id: "test-1",
            ruleName: ruleName,
            score: score,
            comment: comment,
            filePath: filePath,
            lineNumber: lineNumber,
            documentationLink: documentationLink,
            relevantClaudeSkill: relevantClaudeSkill,
            ruleUrl: ruleUrl,
            analysisMethod: analysisMethod,
            ruleHash: ruleHash,
            fileBlobSHA: fileBlobSHA
        )
    }

    // MARK: - toGitHubMarkdown

    @Test("toGitHubMarkdown includes rule name header")
    func markdownIncludesRuleHeader() {
        // Arrange
        let comment = makeComment()

        // Act
        let markdown = comment.toGitHubMarkdown()

        // Assert
        #expect(markdown.contains("**no-force-unwrap**"))
    }

    @Test("toGitHubMarkdown links rule name when ruleUrl is present")
    func markdownLinksRuleName() {
        // Arrange
        let comment = makeComment(ruleUrl: "https://example.com/rule")

        // Act
        let markdown = comment.toGitHubMarkdown()

        // Assert
        #expect(markdown.contains("**[no-force-unwrap](https://example.com/rule)**"))
    }

    @Test("toGitHubMarkdown includes violation comment text")
    func markdownIncludesViolation() {
        // Arrange
        let comment = makeComment(comment: "This is dangerous")

        // Act
        let markdown = comment.toGitHubMarkdown()

        // Assert
        #expect(markdown.contains("This is dangerous"))
    }

    @Test("toGitHubMarkdown includes PR Radar footer")
    func markdownIncludesFooter() {
        // Arrange
        let comment = makeComment()

        // Act
        let markdown = comment.toGitHubMarkdown()

        // Assert
        #expect(markdown.contains("*Assisted by [PR Radar]"))
    }

    @Test("toGitHubMarkdown includes Claude skill when present")
    func markdownIncludesClaudeSkill() {
        // Arrange
        let comment = makeComment(relevantClaudeSkill: "swift-testing")

        // Act
        let markdown = comment.toGitHubMarkdown()

        // Assert
        #expect(markdown.contains("Related Claude Skill: `/swift-testing`"))
    }

    @Test("toGitHubMarkdown includes documentation link when present")
    func markdownIncludesDocLink() {
        // Arrange
        let comment = makeComment(documentationLink: "https://docs.example.com")

        // Act
        let markdown = comment.toGitHubMarkdown()

        // Assert
        #expect(markdown.contains("[Docs](https://docs.example.com)"))
    }

    // MARK: - buildMetadata

    @Test("buildMetadata produces correct metadata from PRComment fields")
    func buildMetadataCorrectFields() {
        // Arrange
        let comment = makeComment(
            ruleName: "use-guard-let",
            filePath: "Sources/Foo.swift",
            lineNumber: 10,
            ruleHash: "hash999",
            fileBlobSHA: "blob777"
        )

        // Act
        let metadata = comment.buildMetadata(prHeadSHA: "commitSHA")

        // Assert
        #expect(metadata.rule.id == "use-guard-let")
        #expect(metadata.rule.hash == "hash999")
        #expect(metadata.fileInfo?.path == "Sources/Foo.swift")
        #expect(metadata.fileInfo?.line == 10)
        #expect(metadata.fileInfo?.blobSHA == "blob777")
        #expect(metadata.prHeadSHA == "commitSHA")
    }

    @Test("buildMetadata handles nil lineNumber and fileBlobSHA")
    func buildMetadataNilOptionals() {
        // Arrange
        let comment = makeComment(lineNumber: nil, fileBlobSHA: nil)

        // Act
        let metadata = comment.buildMetadata(prHeadSHA: "sha")

        // Assert
        #expect(metadata.fileInfo?.line == nil)
        #expect(metadata.fileInfo?.blobSHA == nil)
    }

    @Test("buildMetadata round-trips through toHTMLComment and parse")
    func buildMetadataRoundTrip() {
        // Arrange
        let comment = makeComment(fileBlobSHA: "blob123")
        let metadata = comment.buildMetadata(prHeadSHA: "headsha")

        // Act
        let html = metadata.toHTMLComment()
        let parsed = CommentMetadata.parse(from: html)

        // Assert
        #expect(parsed == metadata)
    }

    // MARK: - effectiveBlobSHA

    @Test("effectiveBlobSHA returns nil for empty string")
    func effectiveBlobSHAEmptyString() {
        // Arrange
        let comment = makeComment(fileBlobSHA: "")

        // Assert
        #expect(comment.effectiveBlobSHA == nil)
    }

    @Test("effectiveBlobSHA returns value for non-empty string")
    func effectiveBlobSHANonEmpty() {
        // Arrange
        let comment = makeComment(fileBlobSHA: "abc123")

        // Assert
        #expect(comment.effectiveBlobSHA == "abc123")
    }

    @Test("effectiveBlobSHA returns nil when fileBlobSHA is nil")
    func effectiveBlobSHANil() {
        // Arrange
        let comment = makeComment(fileBlobSHA: nil)

        // Assert
        #expect(comment.effectiveBlobSHA == nil)
    }
}
