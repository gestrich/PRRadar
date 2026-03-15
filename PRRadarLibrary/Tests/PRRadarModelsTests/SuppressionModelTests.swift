import Testing
@testable import PRRadarModels

@Suite("Suppression model properties")
struct SuppressionModelTests {

    // MARK: - Helpers

    private func makePending(
        suppressionRole: SuppressionRole? = nil
    ) -> PRComment {
        PRComment(
            id: "pending-1",
            ruleName: "import-order",
            score: 6,
            comment: "Import order violation",
            filePath: "Sources/Foo.swift",
            lineNumber: 10,
            ruleHash: "abc123",
            suppressionRole: suppressionRole,
            maxCommentsPerFile: 3
        )
    }

    private func makePosted(
        suppressionRole: SuppressionRole? = nil
    ) -> GitHubReviewComment {
        let metadata = CommentMetadata(
            rule: .init(id: "import-order", hash: "abc123"),
            fileInfo: .init(path: "Sources/Foo.swift", line: 10, blobSHA: nil),
            prHeadSHA: "deadbeef",
            suppressionRole: suppressionRole
        )
        let body = "**import-order**\n\nImport order violation\n\n" + metadata.toHTMLComment()
        return GitHubReviewComment(id: "posted-1", body: body, path: "Sources/Foo.swift", line: 10)
    }

    private func makePostedWithoutMetadata() -> GitHubReviewComment {
        GitHubReviewComment(
            id: "posted-1",
            body: "**import-order**\n\nImport order violation",
            path: "Sources/Foo.swift",
            line: 10
        )
    }

    // MARK: - PRComment.withSuppression

    @Test("withSuppression produces copy with role set")
    func withSuppressionSetsRole() {
        // Arrange
        let original = makePending()

        // Act
        let suppressed = original.withSuppression(role: .suppressed)
        let limiting = original.withSuppression(role: .limiting)

        // Assert
        #expect(suppressed.suppressionRole == .suppressed)
        #expect(limiting.suppressionRole == .limiting)
        #expect(original.suppressionRole == nil)
    }

    @Test("withSuppression preserves all other fields")
    func withSuppressionPreservesFields() {
        // Arrange
        let original = makePending()

        // Act
        let copy = original.withSuppression(role: .limiting)

        // Assert
        #expect(copy.id == original.id)
        #expect(copy.ruleName == original.ruleName)
        #expect(copy.score == original.score)
        #expect(copy.comment == original.comment)
        #expect(copy.filePath == original.filePath)
        #expect(copy.lineNumber == original.lineNumber)
        #expect(copy.ruleHash == original.ruleHash)
        #expect(copy.fileBlobSHA == original.fileBlobSHA)
        #expect(copy.maxCommentsPerFile == original.maxCommentsPerFile)
    }

    // MARK: - ReviewComment.suppressionRole

    @Test("suppressionRole from pending comment")
    func suppressionRoleFromPending() {
        // Arrange
        let pending = makePending(suppressionRole: .limiting)
        let comment = ReviewComment.new(pending: pending)

        // Assert
        #expect(comment.suppressionRole == .limiting)
    }

    @Test("suppressionRole from posted metadata when no pending")
    func suppressionRoleFromPostedMetadata() {
        // Arrange
        let posted = makePosted(suppressionRole: .limiting)
        let comment = ReviewComment.postedOnly(posted: posted)

        // Assert
        #expect(comment.suppressionRole == .limiting)
    }

    @Test("suppressionRole nil when no pending and no metadata")
    func suppressionRoleNilWhenNoMetadata() {
        // Arrange
        let posted = makePostedWithoutMetadata()
        let comment = ReviewComment.postedOnly(posted: posted)

        // Assert
        #expect(comment.suppressionRole == nil)
    }

    @Test("suppressionRole prefers pending over posted metadata")
    func suppressionRolePrefersP() {
        // Arrange — pending says suppressed, posted metadata says limiting
        let pending = makePending(suppressionRole: .suppressed)
        let posted = makePosted(suppressionRole: .limiting)
        let comment = ReviewComment.needsUpdate(pending: pending, posted: posted)

        // Assert
        #expect(comment.suppressionRole == .suppressed)
    }

    // MARK: - ReviewComment.isSuppressed

    @Test("isSuppressed true for suppressed role")
    func isSuppressedTrue() {
        // Arrange
        let pending = makePending(suppressionRole: .suppressed)
        let comment = ReviewComment.new(pending: pending)

        // Assert
        #expect(comment.isSuppressed == true)
    }

    @Test("isSuppressed false for limiting role")
    func isSuppressedFalseForLimiting() {
        // Arrange
        let pending = makePending(suppressionRole: .limiting)
        let comment = ReviewComment.new(pending: pending)

        // Assert
        #expect(comment.isSuppressed == false)
    }

    @Test("isSuppressed false for nil role")
    func isSuppressedFalseForNil() {
        // Arrange
        let pending = makePending()
        let comment = ReviewComment.new(pending: pending)

        // Assert
        #expect(comment.isSuppressed == false)
    }

    // MARK: - ReviewComment.isPending

    @Test("isPending true for .new and .needsUpdate")
    func isPendingTrue() {
        // Arrange
        let newComment = ReviewComment.new(pending: makePending())
        let posted = makePostedWithoutMetadata()
        let updateComment = ReviewComment.needsUpdate(pending: makePending(), posted: posted)

        // Assert
        #expect(newComment.isPending == true)
        #expect(updateComment.isPending == true)
    }

    @Test("isPending false for .redetected and .postedOnly")
    func isPendingFalse() {
        // Arrange
        let posted = makePostedWithoutMetadata()
        let redetected = ReviewComment.redetected(pending: makePending(), posted: posted)
        let postedOnly = ReviewComment.postedOnly(posted: posted)

        // Assert
        #expect(redetected.isPending == false)
        #expect(postedOnly.isPending == false)
    }

    // MARK: - ReviewComment.readyForPosting

    @Test("readyForPosting true when pending and not suppressed")
    func readyForPostingTrue() {
        // Arrange
        let comment = ReviewComment.new(pending: makePending())

        // Assert
        #expect(comment.readyForPosting == true)
    }

    @Test("readyForPosting true when pending with limiting role")
    func readyForPostingTrueForLimiting() {
        // Arrange
        let comment = ReviewComment.new(pending: makePending(suppressionRole: .limiting))

        // Assert
        #expect(comment.readyForPosting == true)
    }

    @Test("readyForPosting false when suppressed")
    func readyForPostingFalseWhenSuppressed() {
        // Arrange
        let comment = ReviewComment.new(pending: makePending(suppressionRole: .suppressed))

        // Assert
        #expect(comment.readyForPosting == false)
    }

    @Test("readyForPosting false when not pending")
    func readyForPostingFalseWhenNotPending() {
        // Arrange
        let posted = makePostedWithoutMetadata()
        let comment = ReviewComment.postedOnly(posted: posted)

        // Assert
        #expect(comment.readyForPosting == false)
    }

    // MARK: - PRComment.buildMetadata with suppression

    @Test("buildMetadata includes suppression role")
    func buildMetadataWithSuppression() {
        // Arrange
        let comment = makePending(suppressionRole: .limiting)

        // Act
        let metadata = comment.buildMetadata(prHeadSHA: "abc123")

        // Assert
        #expect(metadata.suppressionRole == .limiting)
    }

    @Test("buildMetadata omits suppression role when nil")
    func buildMetadataWithoutSuppression() {
        // Arrange
        let comment = makePending()

        // Act
        let metadata = comment.buildMetadata(prHeadSHA: "abc123")

        // Assert
        #expect(metadata.suppressionRole == nil)
    }

    // MARK: - [PRComment].suppressedCount

    @Test("PRComment array suppressedCount filters correctly")
    func prCommentArraySuppressedCount() {
        // Arrange
        let comments = [
            PRComment(id: "1", ruleName: "rule-A", score: 5, comment: "c", filePath: "A.swift", lineNumber: 10, ruleHash: "h", suppressionRole: .suppressed),
            PRComment(id: "2", ruleName: "rule-A", score: 5, comment: "c", filePath: "A.swift", lineNumber: 20, ruleHash: "h", suppressionRole: .suppressed),
            PRComment(id: "3", ruleName: "rule-A", score: 5, comment: "c", filePath: "B.swift", lineNumber: 10, ruleHash: "h", suppressionRole: .suppressed),
            PRComment(id: "4", ruleName: "rule-A", score: 5, comment: "c", filePath: "A.swift", lineNumber: 30, ruleHash: "h", suppressionRole: .limiting),
            PRComment(id: "5", ruleName: "rule-B", score: 5, comment: "c", filePath: "A.swift", lineNumber: 40, ruleHash: "h", suppressionRole: .suppressed),
        ]

        // Act & Assert
        #expect(comments.suppressedCount(forRule: "rule-A", filePath: "A.swift") == 2)
        #expect(comments.suppressedCount(forRule: "rule-A", filePath: "B.swift") == 1)
        #expect(comments.suppressedCount(forRule: "rule-B", filePath: "A.swift") == 1)
        #expect(comments.suppressedCount(forRule: "rule-A", filePath: "C.swift") == 0)
    }

    // MARK: - [ReviewComment].suppressedCount

    @Test("ReviewComment array suppressedCount filters correctly")
    func reviewCommentArraySuppressedCount() {
        // Arrange
        let comments: [ReviewComment] = [
            .new(pending: PRComment(id: "1", ruleName: "rule-A", score: 5, comment: "c", filePath: "A.swift", lineNumber: 10, ruleHash: "h", suppressionRole: .suppressed)),
            .new(pending: PRComment(id: "2", ruleName: "rule-A", score: 5, comment: "c", filePath: "A.swift", lineNumber: 20, ruleHash: "h", suppressionRole: .limiting)),
            .new(pending: PRComment(id: "3", ruleName: "rule-A", score: 5, comment: "c", filePath: "A.swift", lineNumber: 30, ruleHash: "h", suppressionRole: .suppressed)),
        ]

        // Act & Assert
        #expect(comments.suppressedCount(forRule: "rule-A", filePath: "A.swift") == 2)
    }
}
