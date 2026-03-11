import Testing
@testable import PRRadarModels
@testable import PRRadarCLIService

@Suite("ViolationService.reconcile")
struct ViolationReconciliationTests {

    // MARK: - Helpers

    private func makePending(
        id: String = "pending-1",
        ruleName: String = "no-force-unwrap",
        score: Int = 7,
        comment: String = "Avoid force unwraps",
        filePath: String = "Sources/App.swift",
        lineNumber: Int? = 42,
        fileBlobSHA: String? = nil
    ) -> PRComment {
        PRComment(
            id: id,
            ruleName: ruleName,
            score: score,
            comment: comment,
            filePath: filePath,
            lineNumber: lineNumber,
            ruleHash: "abc123",
            fileBlobSHA: fileBlobSHA
        )
    }

    private func makePosted(
        id: String = "posted-1",
        body: String = "**no-force-unwrap**\n\nAvoid force unwraps",
        path: String = "Sources/App.swift",
        line: Int? = 42
    ) -> GitHubReviewComment {
        GitHubReviewComment(
            id: id,
            body: body,
            path: path,
            line: line
        )
    }

    /// Create a v1 posted comment with embedded metadata.
    private func makeV1Posted(
        id: String = "posted-1",
        contentBody: String = "**no-force-unwrap**\n\nAvoid force unwraps",
        path: String = "Sources/App.swift",
        line: Int? = 42,
        ruleId: String = "no-force-unwrap",
        ruleHash: String = "abc123",
        fileBlobSHA: String? = nil,
        prHeadSHA: String = "deadbeef"
    ) -> GitHubReviewComment {
        let metadata = CommentMetadata(
            rule: .init(id: ruleId, hash: ruleHash),
            fileInfo: .init(path: path, line: line, blobSHA: fileBlobSHA),
            prHeadSHA: prHeadSHA
        )
        let fullBody = contentBody + "\n\n" + metadata.toHTMLComment()
        return GitHubReviewComment(
            id: id,
            body: fullBody,
            path: path,
            line: line
        )
    }

    // MARK: - Basic cases

    @Test("Pending only produces all .new")
    func pendingOnlyAllNew() {
        let pending = [makePending(), makePending(id: "pending-2", lineNumber: 50)]
        let result = ViolationService.reconcile(pending: pending, posted: [])

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.state == .new })
    }

    @Test("Posted only produces all .postedOnly")
    func postedOnlyAllPostedOnly() {
        let posted = [makePosted(), makePosted(id: "posted-2", line: 100)]
        let result = ViolationService.reconcile(pending: [], posted: posted)

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.state == .postedOnly })
    }

    @Test("Empty inputs produce empty output")
    func emptyInputsEmptyOutput() {
        let result = ViolationService.reconcile(pending: [], posted: [])
        #expect(result.isEmpty)
    }

    // MARK: - v0 (legacy) matching

    @Test("v0 match produces .needsUpdate to upgrade with metadata")
    func v0MatchProducesNeedsUpdate() {
        let pending = [makePending()]
        let posted = [makePosted()]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 1)
        #expect(result[0].state == .needsUpdate)
        #expect(result[0].pending?.id == "pending-1")
        #expect(result[0].posted?.id == "posted-1")
    }

    @Test("v0: No match when rule name differs")
    func v0NoMatchWhenRuleNameDiffers() {
        let pending = [makePending(ruleName: "no-force-unwrap")]
        let posted = [makePosted(body: "**use-guard-let**\n\nUse guard let instead")]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    @Test("v0: No match when file path differs")
    func v0NoMatchWhenFilePathDiffers() {
        let pending = [makePending(filePath: "Sources/Foo.swift")]
        let posted = [makePosted(path: "Sources/Bar.swift")]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    @Test("v0: No match when line number differs")
    func v0NoMatchWhenLineNumberDiffers() {
        let pending = [makePending(lineNumber: 42)]
        let posted = [makePosted(line: 99)]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    @Test("v0: Multiple pending at same line — only first rule match consumed")
    func v0MultiplePendingOnePosted() {
        let p1 = makePending(id: "p1", ruleName: "no-force-unwrap")
        let p2 = makePending(id: "p2", ruleName: "use-guard-let")
        let posted = [makePosted(body: "**no-force-unwrap**\n\nAvoid force unwraps")]

        let result = ViolationService.reconcile(pending: [p1, p2], posted: posted)

        #expect(result.count == 2)
        let needsUpdate = result.filter { $0.state == .needsUpdate }
        let new = result.filter { $0.state == .new }
        #expect(needsUpdate.count == 1)
        #expect(needsUpdate[0].pending?.id == "p1")
        #expect(new.count == 1)
        #expect(new[0].pending?.id == "p2")
    }

    @Test("v0: Each posted comment consumed at most once")
    func v0PostedConsumedOnce() {
        let p1 = makePending(id: "p1", ruleName: "no-force-unwrap", lineNumber: 42)
        let p2 = makePending(id: "p2", ruleName: "no-force-unwrap", lineNumber: 42)
        let posted = [makePosted(id: "posted-1")]

        let result = ViolationService.reconcile(pending: [p1, p2], posted: posted)

        #expect(result.count == 2)
        let needsUpdate = result.filter { $0.state == .needsUpdate }
        let new = result.filter { $0.state == .new }
        #expect(needsUpdate.count == 1)
        #expect(new.count == 1)
    }

    @Test("v0: File-level comments match when line is nil")
    func v0FileLevelMatching() {
        let pending = [makePending(lineNumber: nil)]
        let posted = [makePosted(line: nil)]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 1)
        #expect(result[0].state == .needsUpdate)
    }

    @Test("v0: File-level pending does not match line-specific posted")
    func v0FileLevelDoesNotMatchLineSpecific() {
        let pending = [makePending(lineNumber: nil)]
        let posted = [makePosted(line: 42)]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    // MARK: - v1 (metadata) matching

    @Test("v1: Exact match with same body produces .redetected")
    func v1ExactMatchSameBody() {
        let p = makePending()
        let posted = [makeV1Posted(contentBody: p.toGitHubMarkdown())]
        let result = ViolationService.reconcile(pending: [p], posted: posted)

        #expect(result.count == 1)
        #expect(result[0].state == .redetected)
        #expect(result[0].pending != nil)
        #expect(result[0].posted != nil)
    }

    @Test("v1: Exact match with different body produces .needsUpdate")
    func v1ExactMatchDifferentBody() {
        let pending = [makePending(comment: "Updated violation message")]
        let posted = [makeV1Posted(contentBody: "**no-force-unwrap**\n\nOriginal message")]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 1)
        #expect(result[0].state == .needsUpdate)
        #expect(result[0].pending != nil)
        #expect(result[0].posted != nil)
    }

    @Test("v1: Line-shifted match with same fileBlobSHA produces .redetected")
    func v1LineShiftedMatch() {
        let pending = [makePending(lineNumber: 50, fileBlobSHA: "blobhash123")]
        let posted = [makeV1Posted(line: 42, fileBlobSHA: "blobhash123")]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 1)
        #expect(result[0].state == .redetected)
    }

    @Test("v1: No match when rule differs")
    func v1NoMatchDifferentRule() {
        let pending = [makePending(ruleName: "use-guard-let")]
        let posted = [makeV1Posted(ruleId: "no-force-unwrap")]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    @Test("v1: No match when file differs")
    func v1NoMatchDifferentFile() {
        let pending = [makePending(filePath: "Sources/Foo.swift")]
        let posted = [makeV1Posted(path: "Sources/Bar.swift")]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    @Test("v1: File-changed (different fileBlobSHA) produces .new")
    func v1FileChangedDifferentBlobSHA() {
        let pending = [makePending(lineNumber: 50, fileBlobSHA: "newblob")]
        let posted = [makeV1Posted(line: 99, fileBlobSHA: "oldblob")]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        // Different line AND different blob SHA → Tier 4 → .new (file was modified)
        // The posted comment is consumed by the match, so only 1 result
        #expect(result.count == 1)
        #expect(result[0].state == .new)
        #expect(result[0].pending?.id == "pending-1")
    }

    @Test("v1: Fallback when no blob SHA available uses body comparison")
    func v1FallbackNoBlobSHA() {
        let p = makePending(lineNumber: 50, fileBlobSHA: nil)
        let posted = [makeV1Posted(contentBody: p.toGitHubMarkdown(), line: 42, fileBlobSHA: nil)]
        let result = ViolationService.reconcile(pending: [p], posted: posted)

        // Same rule + file, different line, no blob SHA → fallback match → body matches → .redetected
        #expect(result.count == 1)
        #expect(result[0].state == .redetected)
    }

    @Test("v1: Fallback with different body produces .needsUpdate")
    func v1FallbackDifferentBody() {
        let pending = [makePending(comment: "Updated message", lineNumber: 50, fileBlobSHA: nil)]
        let posted = [makeV1Posted(contentBody: "**no-force-unwrap**\n\nOriginal message", line: 42, fileBlobSHA: nil)]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 1)
        #expect(result[0].state == .needsUpdate)
    }

    @Test("v1: Each posted comment consumed at most once")
    func v1PostedConsumedOnce() {
        let p1 = makePending(id: "p1", lineNumber: 42)
        let p2 = makePending(id: "p2", lineNumber: 42)
        let posted = [makeV1Posted(id: "g1")]
        let result = ViolationService.reconcile(pending: [p1, p2], posted: posted)

        #expect(result.count == 2)
        let matched = result.filter { $0.state == .redetected || $0.state == .needsUpdate }
        let new = result.filter { $0.state == .new }
        #expect(matched.count == 1)
        #expect(new.count == 1)
    }

    // MARK: - Mixed v0 + v1 scenario

    @Test("Mixed v0 and v1 comments produces correct states")
    func mixedV0AndV1() {
        let p1 = makePending(id: "p1", ruleName: "no-force-unwrap", filePath: "A.swift", lineNumber: 10)
        let p2 = makePending(id: "p2", ruleName: "use-guard-let", filePath: "B.swift", lineNumber: 20)
        let p3 = makePending(id: "p3", ruleName: "no-implicitly-unwrapped", filePath: "C.swift", lineNumber: 30)

        // v1 posted: same rule+file+line, same body → .redetected
        let v1Posted = makeV1Posted(
            id: "g1",
            contentBody: p1.toGitHubMarkdown(),
            path: "A.swift",
            line: 10,
            ruleId: "no-force-unwrap"
        )
        // v0 posted: legacy match → .needsUpdate
        let v0Posted = makePosted(
            id: "g2",
            body: "**use-guard-let**\n\nsome text",
            path: "B.swift",
            line: 20
        )
        // v0 posted: no match → .postedOnly
        let orphaned = makePosted(
            id: "g3",
            body: "**old-rule**\n\ntext",
            path: "D.swift",
            line: 99
        )

        let result = ViolationService.reconcile(pending: [p1, p2, p3], posted: [v1Posted, v0Posted, orphaned])

        #expect(result.count == 4)
        let redetected = result.filter { $0.state == .redetected }
        let needsUpdate = result.filter { $0.state == .needsUpdate }
        let new = result.filter { $0.state == .new }
        let postedOnly = result.filter { $0.state == .postedOnly }
        #expect(redetected.count == 1)
        #expect(redetected[0].pending?.id == "p1")
        #expect(needsUpdate.count == 1)
        #expect(needsUpdate[0].pending?.id == "p2")
        #expect(new.count == 1)
        #expect(new[0].pending?.id == "p3")
        #expect(postedOnly.count == 1)
        #expect(postedOnly[0].posted?.id == "g3")
    }

    @Test("v1 matching preferred over v0 for same comment")
    func v1MatchingPreferredOverV0() {
        let p = makePending()
        // This comment has metadata, so v1 matching should be used
        let posted = [makeV1Posted(contentBody: p.toGitHubMarkdown())]
        let result = ViolationService.reconcile(pending: [p], posted: posted)

        #expect(result.count == 1)
        // v1 exact match with same body → .redetected (not .needsUpdate like v0 would produce)
        #expect(result[0].state == .redetected)
    }
}
