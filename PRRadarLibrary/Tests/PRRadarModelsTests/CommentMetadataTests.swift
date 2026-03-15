import Testing
@testable import PRRadarModels

@Suite("CommentMetadata")
struct CommentMetadataTests {

    // MARK: - Round-trip

    @Test("toHTMLComment then parse produces identical struct")
    func roundTrip() {
        // Arrange
        let original = CommentMetadata(
            rule: .init(id: "no-force-unwrap", hash: "abc123"),
            fileInfo: .init(path: "Sources/App.swift", line: 42, blobSHA: "def456"),
            prHeadSHA: "deadbeef"
        )

        // Act
        let html = original.toHTMLComment()
        let parsed = CommentMetadata.parse(from: "Some comment body\n\n" + html)

        // Assert
        #expect(parsed == original)
    }

    @Test("Round-trip without optional fields")
    func roundTripMinimalFields() {
        // Arrange
        let original = CommentMetadata(
            rule: .init(id: "use-guard-let", hash: "xyz789"),
            fileInfo: .init(path: "Sources/Foo.swift", line: nil, blobSHA: nil),
            prHeadSHA: "cafebabe"
        )

        // Act
        let html = original.toHTMLComment()
        let parsed = CommentMetadata.parse(from: html)

        // Assert
        #expect(parsed == original)
    }

    @Test("Round-trip without fileInfo")
    func roundTripNoFileInfo() {
        // Arrange
        let original = CommentMetadata(
            rule: .init(id: "some-rule", hash: "hash1"),
            fileInfo: nil,
            prHeadSHA: "abc"
        )

        // Act
        let html = original.toHTMLComment()
        let parsed = CommentMetadata.parse(from: html)

        // Assert
        #expect(parsed == original)
    }

    // MARK: - Parse edge cases

    @Test("parse returns nil for body without metadata")
    func parseNoMetadata() {
        // Arrange
        let body = "**no-force-unwrap**\n\nAvoid force unwraps"

        // Act
        let result = CommentMetadata.parse(from: body)

        // Assert
        #expect(result == nil)
    }

    @Test("parse returns nil for empty string")
    func parseEmptyString() {
        #expect(CommentMetadata.parse(from: "") == nil)
    }

    @Test("parse returns nil when required fields are missing")
    func parseMissingRequiredFields() {
        // Arrange — missing pr_head_sha
        let body = """
        Some text
        <!-- prradar:v1
        rule_id: test-rule
        rule_hash: abc
        -->
        """

        // Act
        let result = CommentMetadata.parse(from: body)

        // Assert
        #expect(result == nil)
    }

    @Test("parse returns nil when rule_id is missing")
    func parseMissingRuleId() {
        // Arrange
        let body = """
        <!-- prradar:v1
        rule_hash: abc
        pr_head_sha: deadbeef
        -->
        """

        // Act
        let result = CommentMetadata.parse(from: body)

        // Assert
        #expect(result == nil)
    }

    @Test("parse returns nil for malformed block (no closing tag)")
    func parseMalformedNoClose() {
        // Arrange
        let body = """
        <!-- prradar:v1
        rule_id: test
        rule_hash: abc
        pr_head_sha: deadbeef
        """

        // Act
        let result = CommentMetadata.parse(from: body)

        // Assert
        #expect(result == nil)
    }

    @Test("parse handles metadata embedded in larger body")
    func parseEmbeddedInBody() {
        // Arrange
        let metadata = CommentMetadata(
            rule: .init(id: "test-rule", hash: "hash1"),
            fileInfo: .init(path: "file.swift", line: 10, blobSHA: "blob1"),
            prHeadSHA: "sha1"
        )
        let body = "**test-rule**\n\nViolation message\n\n*Footer*\n\n" + metadata.toHTMLComment()

        // Act
        let parsed = CommentMetadata.parse(from: body)

        // Assert
        #expect(parsed == metadata)
    }

    // MARK: - stripMetadata

    @Test("stripMetadata removes the metadata block")
    func stripMetadataRemovesBlock() {
        // Arrange
        let metadata = CommentMetadata(
            rule: .init(id: "test-rule", hash: "h1"),
            fileInfo: .init(path: "f.swift", line: 1, blobSHA: nil),
            prHeadSHA: "sha"
        )
        let contentBody = "**test-rule**\n\nSome violation"
        let fullBody = contentBody + "\n\n" + metadata.toHTMLComment()

        // Act
        let stripped = CommentMetadata.stripMetadata(from: fullBody)

        // Assert
        #expect(stripped == contentBody)
    }

    @Test("stripMetadata on body without metadata returns unchanged")
    func stripMetadataNoOp() {
        // Arrange
        let body = "**rule**\n\nJust a comment"

        // Act
        let stripped = CommentMetadata.stripMetadata(from: body)

        // Assert
        #expect(stripped == body)
    }

    // MARK: - Suppression role

    @Test("Round-trip with limiting suppression role")
    func roundTripWithLimitingRole() {
        // Arrange
        let original = CommentMetadata(
            rule: .init(id: "import-order", hash: "abc"),
            fileInfo: .init(path: "Sources/Foo.swift", line: 12, blobSHA: nil),
            prHeadSHA: "deadbeef",
            suppressionRole: .limiting
        )

        // Act
        let html = original.toHTMLComment()
        let parsed = CommentMetadata.parse(from: "Body text\n\n" + html)

        // Assert
        #expect(parsed == original)
        #expect(parsed?.suppressionRole == .limiting)
    }

    @Test("Round-trip with suppressed role")
    func roundTripWithSuppressedRole() {
        // Arrange
        let original = CommentMetadata(
            rule: .init(id: "import-order", hash: "abc"),
            fileInfo: .init(path: "Sources/Foo.swift", line: 45, blobSHA: nil),
            prHeadSHA: "deadbeef",
            suppressionRole: .suppressed
        )

        // Act
        let html = original.toHTMLComment()
        let parsed = CommentMetadata.parse(from: html)

        // Assert
        #expect(parsed == original)
        #expect(parsed?.suppressionRole == .suppressed)
    }

    @Test("Parse v1 metadata without suppression_role returns nil role")
    func parseV1WithoutSuppressionRole() {
        // Arrange — existing v1 format without suppression_role
        let body = """
        <!-- prradar:v1
        rule_id: test-rule
        rule_hash: abc
        file: Sources/Foo.swift
        line: 10
        pr_head_sha: deadbeef
        -->
        """

        // Act
        let parsed = CommentMetadata.parse(from: body)

        // Assert
        #expect(parsed != nil)
        #expect(parsed?.suppressionRole == nil)
    }

    @Test("Parse ignores unknown suppression_role value")
    func parseUnknownSuppressionRole() {
        // Arrange
        let body = """
        <!-- prradar:v1
        rule_id: test-rule
        rule_hash: abc
        pr_head_sha: deadbeef
        suppression_role: unknown_value
        -->
        """

        // Act
        let parsed = CommentMetadata.parse(from: body)

        // Assert
        #expect(parsed != nil)
        #expect(parsed?.suppressionRole == nil)
    }

    @Test("toHTMLComment omits suppression_role when nil")
    func htmlCommentOmitsNilSuppressionRole() {
        // Arrange
        let metadata = CommentMetadata(
            rule: .init(id: "test", hash: "h1"),
            fileInfo: nil,
            prHeadSHA: "sha1"
        )

        // Act
        let html = metadata.toHTMLComment()

        // Assert
        #expect(!html.contains("suppression_role"))
    }

    // MARK: - toHTMLComment format

    @Test("toHTMLComment produces expected format")
    func htmlCommentFormat() {
        // Arrange
        let metadata = CommentMetadata(
            rule: .init(id: "service-locator-usage", hash: "a1b2c3d4"),
            fileInfo: .init(path: "Sources/App/ServiceLocator.swift", line: 42, blobSHA: "789xyz"),
            prHeadSHA: "abc123def456"
        )

        // Act
        let html = metadata.toHTMLComment()

        // Assert
        #expect(html.hasPrefix("<!-- prradar:v1"))
        #expect(html.hasSuffix("-->"))
        #expect(html.contains("rule_id: service-locator-usage"))
        #expect(html.contains("rule_hash: a1b2c3d4"))
        #expect(html.contains("file: Sources/App/ServiceLocator.swift"))
        #expect(html.contains("line: 42"))
        #expect(html.contains("file_blob_sha: 789xyz"))
        #expect(html.contains("pr_head_sha: abc123def456"))
    }
}
