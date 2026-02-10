import Testing
@testable import PRRadarModels
@testable import PRRadarCLIService

@Suite("ViolationService.reconcile")
struct ViolationReconciliationTests {

    // MARK: - Helpers

    private func makePending(
        id: String = "pending-1",
        ruleName: String = "no-force-unwrap",
        filePath: String = "Sources/App.swift",
        lineNumber: Int? = 42
    ) -> PRComment {
        PRComment(
            id: id,
            ruleName: ruleName,
            score: 7,
            comment: "Avoid force unwraps",
            filePath: filePath,
            lineNumber: lineNumber
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

    @Test("Matching pending and posted produces .redetected")
    func matchingProducesRedetected() {
        let pending = [makePending()]
        let posted = [makePosted()]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 1)
        #expect(result[0].state == .redetected)
        #expect(result[0].pending?.id == "pending-1")
        #expect(result[0].posted?.id == "posted-1")
    }

    @Test("Empty inputs produce empty output")
    func emptyInputsEmptyOutput() {
        let result = ViolationService.reconcile(pending: [], posted: [])
        #expect(result.isEmpty)
    }

    // MARK: - Matching heuristic

    @Test("No match when rule name differs")
    func noMatchWhenRuleNameDiffers() {
        let pending = [makePending(ruleName: "no-force-unwrap")]
        let posted = [makePosted(body: "**use-guard-let**\n\nUse guard let instead")]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    @Test("No match when file path differs")
    func noMatchWhenFilePathDiffers() {
        let pending = [makePending(filePath: "Sources/Foo.swift")]
        let posted = [makePosted(path: "Sources/Bar.swift")]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    @Test("No match when line number differs")
    func noMatchWhenLineNumberDiffers() {
        let pending = [makePending(lineNumber: 42)]
        let posted = [makePosted(line: 99)]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    // MARK: - Multiple pending, one posted

    @Test("Multiple pending at same line — only first rule match consumed")
    func multiplePendingOnePosted() {
        let p1 = makePending(id: "p1", ruleName: "no-force-unwrap")
        let p2 = makePending(id: "p2", ruleName: "use-guard-let")
        let posted = [makePosted(body: "**no-force-unwrap**\n\nAvoid force unwraps")]

        let result = ViolationService.reconcile(pending: [p1, p2], posted: posted)

        #expect(result.count == 2)
        let redetected = result.filter { $0.state == .redetected }
        let new = result.filter { $0.state == .new }
        #expect(redetected.count == 1)
        #expect(redetected[0].pending?.id == "p1")
        #expect(new.count == 1)
        #expect(new[0].pending?.id == "p2")
    }

    @Test("Each posted comment consumed at most once")
    func postedConsumedOnce() {
        let p1 = makePending(id: "p1", ruleName: "no-force-unwrap", lineNumber: 42)
        let p2 = makePending(id: "p2", ruleName: "no-force-unwrap", lineNumber: 42)
        let posted = [makePosted(id: "posted-1")]

        let result = ViolationService.reconcile(pending: [p1, p2], posted: posted)

        #expect(result.count == 2)
        let redetected = result.filter { $0.state == .redetected }
        let new = result.filter { $0.state == .new }
        #expect(redetected.count == 1)
        #expect(new.count == 1)
    }

    // MARK: - File-level (no line number)

    @Test("File-level comments match when line is nil")
    func fileLevelMatching() {
        let pending = [makePending(lineNumber: nil)]
        let posted = [makePosted(line: nil)]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 1)
        #expect(result[0].state == .redetected)
    }

    @Test("File-level pending does not match line-specific posted")
    func fileLevelDoesNotMatchLineSpecific() {
        let pending = [makePending(lineNumber: nil)]
        let posted = [makePosted(line: 42)]
        let result = ViolationService.reconcile(pending: pending, posted: posted)

        #expect(result.count == 2)
        let states = Set(result.map { $0.state })
        #expect(states == [.new, .postedOnly])
    }

    // MARK: - Mixed scenario

    @Test("Mixed pending and posted produces correct states")
    func mixedScenario() {
        let p1 = makePending(id: "p1", ruleName: "no-force-unwrap", filePath: "A.swift", lineNumber: 10)
        let p2 = makePending(id: "p2", ruleName: "use-guard-let", filePath: "B.swift", lineNumber: 20)
        let posted1 = makePosted(id: "g1", body: "**no-force-unwrap**\n\ntext", path: "A.swift", line: 10)
        let posted2 = makePosted(id: "g2", body: "**old-rule**\n\ntext", path: "C.swift", line: 30)

        let result = ViolationService.reconcile(pending: [p1, p2], posted: [posted1, posted2])

        #expect(result.count == 3)
        let redetected = result.filter { $0.state == .redetected }
        let new = result.filter { $0.state == .new }
        let postedOnly = result.filter { $0.state == .postedOnly }
        #expect(redetected.count == 1)
        #expect(redetected[0].pending?.id == "p1")
        #expect(redetected[0].posted?.id == "g1")
        #expect(new.count == 1)
        #expect(new[0].pending?.id == "p2")
        #expect(postedOnly.count == 1)
        #expect(postedOnly[0].posted?.id == "g2")
    }
}
