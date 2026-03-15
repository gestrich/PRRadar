import Testing
@testable import PRRadarModels
@testable import PRRadarCLIService

@Suite("CommentSuppressionService")
struct CommentSuppressionServiceTests {

    // MARK: - Helpers

    private func makePending(
        id: String = "pending-1",
        ruleName: String = "import-order",
        score: Int = 6,
        comment: String = "Import order violation",
        filePath: String = "Sources/Foo.swift",
        lineNumber: Int? = 10,
        ruleHash: String = "abc123",
        fileBlobSHA: String? = nil,
        maxCommentsPerFile: Int? = 3
    ) -> PRComment {
        PRComment(
            id: id,
            ruleName: ruleName,
            score: score,
            comment: comment,
            filePath: filePath,
            lineNumber: lineNumber,
            ruleHash: ruleHash,
            fileBlobSHA: fileBlobSHA,
            maxCommentsPerFile: maxCommentsPerFile
        )
    }

    private func makePosted(
        id: String = "posted-1",
        body: String = "**import-order**\n\nImport order violation",
        path: String = "Sources/Foo.swift",
        line: Int? = 10,
        isResolved: Bool = false,
        isOutdated: Bool = false
    ) -> GitHubReviewComment {
        GitHubReviewComment(
            id: id,
            body: body,
            path: path,
            line: line,
            isResolved: isResolved,
            isOutdated: isOutdated
        )
    }

    private func makeV1Posted(
        id: String = "posted-1",
        contentBody: String = "**import-order**\n\nImport order violation",
        path: String = "Sources/Foo.swift",
        line: Int? = 10,
        ruleId: String = "import-order",
        ruleHash: String = "abc123",
        fileBlobSHA: String? = nil,
        prHeadSHA: String = "deadbeef",
        suppressionRole: SuppressionRole? = nil,
        isResolved: Bool = false,
        isOutdated: Bool = false
    ) -> GitHubReviewComment {
        let metadata = CommentMetadata(
            rule: .init(id: ruleId, hash: ruleHash),
            fileInfo: .init(path: path, line: line, blobSHA: fileBlobSHA),
            prHeadSHA: prHeadSHA,
            suppressionRole: suppressionRole
        )
        let fullBody = contentBody + "\n\n" + metadata.toHTMLComment()
        return GitHubReviewComment(
            id: id,
            body: fullBody,
            path: path,
            line: line,
            isResolved: isResolved,
            isOutdated: isOutdated
        )
    }

    // MARK: - Under limit: no suppression

    @Test("Under limit — all pending comments remain normal")
    func underLimitNoSuppression() {
        // Arrange
        let comments: [ReviewComment] = [
            .new(pending: makePending(id: "p1", lineNumber: 10, maxCommentsPerFile: 5)),
            .new(pending: makePending(id: "p2", lineNumber: 20, maxCommentsPerFile: 5)),
            .new(pending: makePending(id: "p3", lineNumber: 30, maxCommentsPerFile: 5)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert
        #expect(result.suppressedCount == 0)
        #expect(result.comments.allSatisfy { $0.suppressionRole == nil })
    }

    @Test("Exactly at limit — no suppression needed")
    func exactlyAtLimitNoSuppression() {
        // Arrange
        let comments: [ReviewComment] = [
            .new(pending: makePending(id: "p1", lineNumber: 10, maxCommentsPerFile: 3)),
            .new(pending: makePending(id: "p2", lineNumber: 20, maxCommentsPerFile: 3)),
            .new(pending: makePending(id: "p3", lineNumber: 30, maxCommentsPerFile: 3)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert
        #expect(result.suppressedCount == 0)
        #expect(result.comments.allSatisfy { $0.suppressionRole == nil })
    }

    // MARK: - At/over limit: last becomes limiting

    @Test("Over limit — last posted becomes limiting, rest suppressed")
    func overLimitCorrectSplit() {
        // Arrange — limit 2, 5 pending
        let comments: [ReviewComment] = [
            .new(pending: makePending(id: "p1", lineNumber: 10, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p2", lineNumber: 20, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p3", lineNumber: 30, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p4", lineNumber: 40, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p5", lineNumber: 50, maxCommentsPerFile: 2)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert
        #expect(result.suppressedCount == 3)

        let sorted = result.comments.sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(sorted[0].suppressionRole == nil)       // line 10: normal
        #expect(sorted[1].suppressionRole == .limiting)  // line 20: limiting (2nd = last posted)
        #expect(sorted[2].suppressionRole == .suppressed) // line 30: suppressed
        #expect(sorted[3].suppressionRole == .suppressed) // line 40: suppressed
        #expect(sorted[4].suppressionRole == .suppressed) // line 50: suppressed
    }

    @Test("Limit of 1 — first becomes limiting, rest suppressed")
    func limitOfOne() {
        // Arrange
        let comments: [ReviewComment] = [
            .new(pending: makePending(id: "p1", lineNumber: 10, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p2", lineNumber: 20, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p3", lineNumber: 30, maxCommentsPerFile: 1)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert
        #expect(result.suppressedCount == 2)

        let sorted = result.comments.sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(sorted[0].suppressionRole == .limiting)
        #expect(sorted[1].suppressionRole == .suppressed)
        #expect(sorted[2].suppressionRole == .suppressed)
    }

    // MARK: - Posted comments count toward limit

    @Test("Already-posted comments count toward limit")
    func postedCountsTowardLimit() {
        // Arrange — limit 3, 2 already posted (redetected), 3 new pending
        let posted1 = makePosted(id: "gh-1", line: 5)
        let posted2 = makePosted(id: "gh-2", line: 8)
        let comments: [ReviewComment] = [
            .redetected(pending: makePending(id: "p1", lineNumber: 5, maxCommentsPerFile: 3), posted: posted1),
            .redetected(pending: makePending(id: "p2", lineNumber: 8, maxCommentsPerFile: 3), posted: posted2),
            .new(pending: makePending(id: "p3", lineNumber: 15, maxCommentsPerFile: 3)),
            .new(pending: makePending(id: "p4", lineNumber: 25, maxCommentsPerFile: 3)),
            .new(pending: makePending(id: "p5", lineNumber: 35, maxCommentsPerFile: 3)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — 2 posted + 1 new = 3 (limit), so only 1 new can post (as limiting), 2 suppressed
        #expect(result.suppressedCount == 2)

        let newComments = result.comments.filter { $0.state == .new }
        let sorted = newComments.sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(sorted[0].suppressionRole == .limiting)   // line 15
        #expect(sorted[1].suppressionRole == .suppressed)  // line 25
        #expect(sorted[2].suppressionRole == .suppressed)  // line 35
    }

    @Test("PostedOnly comments without pending are not grouped and don't count toward limit")
    func postedOnlyNotGrouped() {
        // Arrange — limit 2, 2 postedOnly (no pending → no ruleName → not grouped), 3 new pending
        let posted1 = makePosted(id: "gh-1", line: 5)
        let posted2 = makePosted(id: "gh-2", line: 8)
        let comments: [ReviewComment] = [
            .postedOnly(posted: posted1),
            .postedOnly(posted: posted2),
            .new(pending: makePending(id: "p1", lineNumber: 15, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p2", lineNumber: 25, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p3", lineNumber: 35, maxCommentsPerFile: 2)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — postedOnly has no ruleName so isn't in any group
        // Only the 3 new comments form a group, limit 2: first normal, second limiting, third suppressed
        #expect(result.suppressedCount == 1)

        let newComments = result.comments.filter { $0.state == .new }
            .sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(newComments[0].suppressionRole == nil)
        #expect(newComments[1].suppressionRole == .limiting)
        #expect(newComments[2].suppressionRole == .suppressed)
    }

    // MARK: - Resolved posted comment doesn't count

    @Test("Resolved posted comment doesn't count toward limit")
    func resolvedDoesNotCount() {
        // Arrange — limit 2, 1 resolved posted, 1 active posted, 2 new
        let resolvedPosted = makePosted(id: "gh-1", line: 5, isResolved: true)
        let activePosted = makePosted(id: "gh-2", line: 8)
        let comments: [ReviewComment] = [
            .redetected(pending: makePending(id: "p1", lineNumber: 5, maxCommentsPerFile: 2), posted: resolvedPosted),
            .redetected(pending: makePending(id: "p2", lineNumber: 8, maxCommentsPerFile: 2), posted: activePosted),
            .new(pending: makePending(id: "p3", lineNumber: 15, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p4", lineNumber: 25, maxCommentsPerFile: 2)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — 1 active posted + 1 new = 2 (limit reached), second new is suppressed
        // But the resolved one doesn't count, so: postedCount=1, remaining=1
        // 2 pending (.new), remaining=1: first gets limiting, second suppressed
        #expect(result.suppressedCount == 1)

        let newComments = result.comments.filter { $0.state == .new }
        let sorted = newComments.sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(sorted[0].suppressionRole == .limiting)
        #expect(sorted[1].suppressionRole == .suppressed)
    }

    @Test("Outdated posted comment doesn't count toward limit")
    func outdatedDoesNotCount() {
        // Arrange — limit 1, 1 outdated posted, 2 new
        let outdatedPosted = makePosted(id: "gh-1", line: 5, isOutdated: true)
        let comments: [ReviewComment] = [
            .redetected(pending: makePending(id: "p1", lineNumber: 5, maxCommentsPerFile: 1), posted: outdatedPosted),
            .new(pending: makePending(id: "p2", lineNumber: 15, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p3", lineNumber: 25, maxCommentsPerFile: 1)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — outdated doesn't count, postedCount=0, remaining=1, 2 new pending
        // first new → limiting, second → suppressed
        #expect(result.suppressedCount == 1)

        let newComments = result.comments.filter { $0.state == .new }
        let sorted = newComments.sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(sorted[0].suppressionRole == .limiting)
        #expect(sorted[1].suppressionRole == .suppressed)
    }

    // MARK: - Multiple rules on same file

    @Test("Multiple rules on same file have independent limits")
    func multipleRulesIndependentLimits() {
        // Arrange — 2 rules, each with limit 1, on same file
        let comments: [ReviewComment] = [
            .new(pending: makePending(id: "p1", ruleName: "rule-A", lineNumber: 10, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p2", ruleName: "rule-A", lineNumber: 20, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p3", ruleName: "rule-B", lineNumber: 10, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p4", ruleName: "rule-B", lineNumber: 20, maxCommentsPerFile: 1)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — each rule independently: 1 limiting + 1 suppressed
        #expect(result.suppressedCount == 2)

        let ruleA = result.comments.filter { $0.ruleName == "rule-A" }
            .sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(ruleA[0].suppressionRole == .limiting)
        #expect(ruleA[1].suppressionRole == .suppressed)

        let ruleB = result.comments.filter { $0.ruleName == "rule-B" }
            .sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(ruleB[0].suppressionRole == .limiting)
        #expect(ruleB[1].suppressionRole == .suppressed)
    }

    // MARK: - Multiple files for same rule

    @Test("Multiple files for same rule have independent limits")
    func multipleFilesIndependentLimits() {
        // Arrange — same rule, limit 1, 2 violations per file
        let comments: [ReviewComment] = [
            .new(pending: makePending(id: "p1", filePath: "A.swift", lineNumber: 10, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p2", filePath: "A.swift", lineNumber: 20, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p3", filePath: "B.swift", lineNumber: 10, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p4", filePath: "B.swift", lineNumber: 20, maxCommentsPerFile: 1)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — each file independently: 1 limiting + 1 suppressed
        #expect(result.suppressedCount == 2)

        let fileA = result.comments.filter { $0.filePath == "A.swift" }
            .sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(fileA[0].suppressionRole == .limiting)
        #expect(fileA[1].suppressionRole == .suppressed)

        let fileB = result.comments.filter { $0.filePath == "B.swift" }
            .sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(fileB[0].suppressionRole == .limiting)
        #expect(fileB[1].suppressionRole == .suppressed)
    }

    // MARK: - No limit (nil maxCommentsPerFile)

    @Test("No limit — all comments pass through unchanged")
    func noLimitAllPassThrough() {
        // Arrange
        let comments: [ReviewComment] = [
            .new(pending: makePending(id: "p1", lineNumber: 10, maxCommentsPerFile: nil)),
            .new(pending: makePending(id: "p2", lineNumber: 20, maxCommentsPerFile: nil)),
            .new(pending: makePending(id: "p3", lineNumber: 30, maxCommentsPerFile: nil)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert
        #expect(result.suppressedCount == 0)
        #expect(result.comments.allSatisfy { $0.suppressionRole == nil })
    }

    // MARK: - needsUpdate comments are pending

    @Test("needsUpdate comments are treated as pending")
    func needsUpdateTreatedAsPending() {
        // Arrange — limit 1, 2 needsUpdate
        let posted1 = makePosted(id: "gh-1", line: 10)
        let posted2 = makePosted(id: "gh-2", line: 20)
        let comments: [ReviewComment] = [
            .needsUpdate(pending: makePending(id: "p1", lineNumber: 10, maxCommentsPerFile: 1), posted: posted1),
            .needsUpdate(pending: makePending(id: "p2", lineNumber: 20, maxCommentsPerFile: 1), posted: posted2),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — both are pending, posted doesn't count (needsUpdate posted aren't counted in postedCount)
        // postedCount = 0, remaining = 1, 2 pending: first limiting, second suppressed
        #expect(result.suppressedCount == 1)

        let sorted = result.comments.sorted { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }
        #expect(sorted[0].suppressionRole == .limiting)
        #expect(sorted[1].suppressionRole == .suppressed)
    }

    // MARK: - Empty input

    @Test("Empty comment list returns empty result")
    func emptyInput() {
        // Act
        let result = CommentSuppressionService.applySuppression(to: [])

        // Assert
        #expect(result.comments.isEmpty)
        #expect(result.suppressedCount == 0)
    }

    // MARK: - All posted, no pending

    @Test("All posted, no pending — nothing changes")
    func allPostedNoPending() {
        // Arrange
        let comments: [ReviewComment] = [
            .postedOnly(posted: makePosted(id: "gh-1", line: 10)),
            .postedOnly(posted: makePosted(id: "gh-2", line: 20)),
            .postedOnly(posted: makePosted(id: "gh-3", line: 30)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert
        #expect(result.suppressedCount == 0)
        #expect(result.comments.allSatisfy { $0.suppressionRole == nil })
    }

    // MARK: - Remaining <= 0 suppresses all pending

    @Test("When posted count exceeds limit, all new pending are suppressed")
    func postedExceedsLimitAllSuppressed() {
        // Arrange — limit 2, 3 active posted, 2 new
        let comments: [ReviewComment] = [
            .redetected(pending: makePending(id: "p1", lineNumber: 5, maxCommentsPerFile: 2), posted: makePosted(id: "gh-1", line: 5)),
            .redetected(pending: makePending(id: "p2", lineNumber: 8, maxCommentsPerFile: 2), posted: makePosted(id: "gh-2", line: 8)),
            .postedOnly(posted: makePosted(id: "gh-3", line: 12)),
            .new(pending: makePending(id: "p3", lineNumber: 15, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p4", lineNumber: 25, maxCommentsPerFile: 2)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — 3 active posted, remaining = 2-3 = -1 ≤ 0, all 2 new are suppressed
        #expect(result.suppressedCount == 2)

        let newComments = result.comments.filter { $0.state == .new }
        #expect(newComments.allSatisfy { $0.suppressionRole == .suppressed })
    }

    // MARK: - Line number ordering

    @Test("Comments are ordered by line number for deterministic limiting")
    func lineNumberOrdering() {
        // Arrange — unsorted input, limit 2
        let comments: [ReviewComment] = [
            .new(pending: makePending(id: "p3", lineNumber: 50, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p1", lineNumber: 10, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p2", lineNumber: 30, maxCommentsPerFile: 2)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — line 10 normal, line 30 limiting, line 50 suppressed
        #expect(result.suppressedCount == 1)

        let byId = Dictionary(uniqueKeysWithValues: result.comments.map { ($0.pending?.id ?? "", $0) })
        #expect(byId["p1"]?.suppressionRole == nil)
        #expect(byId["p2"]?.suppressionRole == .limiting)
        #expect(byId["p3"]?.suppressionRole == .suppressed)
    }

    // MARK: - Mixed states with suppression

    @Test("Mix of new and needsUpdate with redetected posted")
    func mixedStatesWithSuppression() {
        // Arrange — limit 2, 1 redetected (counts as posted), 1 needsUpdate (pending), 2 new (pending)
        let comments: [ReviewComment] = [
            .redetected(
                pending: makePending(id: "p1", lineNumber: 5, maxCommentsPerFile: 2),
                posted: makePosted(id: "gh-1", line: 5)
            ),
            .needsUpdate(
                pending: makePending(id: "p2", lineNumber: 12, maxCommentsPerFile: 2),
                posted: makePosted(id: "gh-2", line: 12)
            ),
            .new(pending: makePending(id: "p3", lineNumber: 20, maxCommentsPerFile: 2)),
            .new(pending: makePending(id: "p4", lineNumber: 30, maxCommentsPerFile: 2)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert — 1 active posted (redetected), remaining = 2 - 1 = 1
        // 3 pending (needsUpdate + 2 new), sorted by line: 12, 20, 30
        // First pending (line 12) → limiting, rest suppressed
        #expect(result.suppressedCount == 2)

        let byId = Dictionary(uniqueKeysWithValues: result.comments.map {
            let id = $0.pending?.id ?? $0.posted?.id ?? ""
            return (id, $0)
        })
        #expect(byId["p1"]?.suppressionRole == nil)       // redetected, not pending
        #expect(byId["p2"]?.suppressionRole == .limiting)  // needsUpdate, line 12
        #expect(byId["p3"]?.suppressionRole == .suppressed) // new, line 20
        #expect(byId["p4"]?.suppressionRole == .suppressed) // new, line 30
    }

    // MARK: - suppressedCount helper

    @Test("suppressedCount helper returns correct count for rule+file")
    func suppressedCountHelper() {
        // Arrange
        let comments: [ReviewComment] = [
            .new(pending: makePending(id: "p1", ruleName: "rule-A", filePath: "A.swift", lineNumber: 10, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p2", ruleName: "rule-A", filePath: "A.swift", lineNumber: 20, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p3", ruleName: "rule-A", filePath: "B.swift", lineNumber: 10, maxCommentsPerFile: 1)),
            .new(pending: makePending(id: "p4", ruleName: "rule-A", filePath: "B.swift", lineNumber: 20, maxCommentsPerFile: 1)),
        ]

        // Act
        let result = CommentSuppressionService.applySuppression(to: comments)

        // Assert
        let countA = CommentSuppressionService.suppressedCount(
            in: result.comments, ruleName: "rule-A", filePath: "A.swift"
        )
        let countB = CommentSuppressionService.suppressedCount(
            in: result.comments, ruleName: "rule-A", filePath: "B.swift"
        )
        #expect(countA == 1)
        #expect(countB == 1)
    }
}
