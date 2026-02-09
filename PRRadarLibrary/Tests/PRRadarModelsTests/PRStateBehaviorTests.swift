import Testing
@testable import PRRadarModels

@Suite("PRState Behavior")
struct PRStateBehaviorTests {

    // MARK: - apiStateValue

    @Test("apiStateValue maps open to 'open'")
    func apiStateValueOpen() {
        #expect(PRState.open.apiStateValue == "open")
    }

    @Test("apiStateValue maps draft to 'open'")
    func apiStateValueDraft() {
        #expect(PRState.draft.apiStateValue == "open")
    }

    @Test("apiStateValue maps closed to 'closed'")
    func apiStateValueClosed() {
        #expect(PRState.closed.apiStateValue == "closed")
    }

    @Test("apiStateValue maps merged to 'closed'")
    func apiStateValueMerged() {
        #expect(PRState.merged.apiStateValue == "closed")
    }

    // MARK: - fromCLIString

    @Test("fromCLIString parses 'open'")
    func fromCLIStringOpen() {
        #expect(PRState.fromCLIString("open") == .open)
    }

    @Test("fromCLIString parses 'draft'")
    func fromCLIStringDraft() {
        #expect(PRState.fromCLIString("draft") == .draft)
    }

    @Test("fromCLIString parses 'closed'")
    func fromCLIStringClosed() {
        #expect(PRState.fromCLIString("closed") == .closed)
    }

    @Test("fromCLIString parses 'merged'")
    func fromCLIStringMerged() {
        #expect(PRState.fromCLIString("merged") == .merged)
    }

    @Test("fromCLIString is case-insensitive")
    func fromCLIStringCaseInsensitive() {
        #expect(PRState.fromCLIString("OPEN") == .open)
        #expect(PRState.fromCLIString("Draft") == .draft)
        #expect(PRState.fromCLIString("CLOSED") == .closed)
        #expect(PRState.fromCLIString("Merged") == .merged)
    }

    @Test("fromCLIString returns nil for unrecognized values")
    func fromCLIStringUnrecognized() {
        #expect(PRState.fromCLIString("all") == nil)
        #expect(PRState.fromCLIString("invalid") == nil)
        #expect(PRState.fromCLIString("") == nil)
    }

    // MARK: - enhancedState post-filtering

    @Test("enhancedState returns .open for open non-draft PR")
    func enhancedStateOpen() {
        let pr = GitHubPullRequest(number: 1, title: "Test", state: "open", isDraft: false)
        #expect(pr.enhancedState == .open)
    }

    @Test("enhancedState returns .draft for open draft PR")
    func enhancedStateDraft() {
        let pr = GitHubPullRequest(number: 1, title: "Test", state: "open", isDraft: true)
        #expect(pr.enhancedState == .draft)
    }

    @Test("enhancedState returns .closed for closed non-merged PR")
    func enhancedStateClosed() {
        let pr = GitHubPullRequest(number: 1, title: "Test", state: "closed")
        #expect(pr.enhancedState == .closed)
    }

    @Test("enhancedState returns .merged for closed PR with mergedAt")
    func enhancedStateMerged() {
        let pr = GitHubPullRequest(number: 1, title: "Test", state: "closed", mergedAt: "2025-01-01T00:00:00Z")
        #expect(pr.enhancedState == .merged)
    }

    @Test("enhancedState defaults to .open for unknown state")
    func enhancedStateDefault() {
        let pr = GitHubPullRequest(number: 1, title: "Test", state: "unknown")
        #expect(pr.enhancedState == .open)
    }

    @Test("enhancedState defaults to .open for nil state")
    func enhancedStateNil() {
        let pr = GitHubPullRequest(number: 1, title: "Test")
        #expect(pr.enhancedState == .open)
    }

    // MARK: - Post-filtering scenarios

    @Test("filtering by .draft only returns draft PRs from open results")
    func postFilterDraft() {
        let prs = [
            GitHubPullRequest(number: 1, title: "Open PR", state: "open", isDraft: false),
            GitHubPullRequest(number: 2, title: "Draft PR", state: "open", isDraft: true),
            GitHubPullRequest(number: 3, title: "Another Open", state: "open", isDraft: false),
        ]
        let filtered = prs.filter { $0.enhancedState == PRState.draft }
        #expect(filtered.count == 1)
        #expect(filtered[0].number == 2)
    }

    @Test("filtering by .merged only returns merged PRs from closed results")
    func postFilterMerged() {
        let prs = [
            GitHubPullRequest(number: 1, title: "Closed PR", state: "closed"),
            GitHubPullRequest(number: 2, title: "Merged PR", state: "closed", mergedAt: "2025-01-01T00:00:00Z"),
            GitHubPullRequest(number: 3, title: "Also Merged", state: "closed", mergedAt: "2025-01-02T00:00:00Z"),
        ]
        let filtered = prs.filter { $0.enhancedState == PRState.merged }
        #expect(filtered.count == 2)
        #expect(filtered[0].number == 2)
        #expect(filtered[1].number == 3)
    }

    @Test("filtering by .open excludes drafts")
    func postFilterOpenExcludesDrafts() {
        let prs = [
            GitHubPullRequest(number: 1, title: "Open PR", state: "open", isDraft: false),
            GitHubPullRequest(number: 2, title: "Draft PR", state: "open", isDraft: true),
        ]
        let filtered = prs.filter { $0.enhancedState == PRState.open }
        #expect(filtered.count == 1)
        #expect(filtered[0].number == 1)
    }

    @Test("filtering by .closed excludes merged")
    func postFilterClosedExcludesMerged() {
        let prs = [
            GitHubPullRequest(number: 1, title: "Closed PR", state: "closed"),
            GitHubPullRequest(number: 2, title: "Merged PR", state: "closed", mergedAt: "2025-01-01T00:00:00Z"),
        ]
        let filtered = prs.filter { $0.enhancedState == PRState.closed }
        #expect(filtered.count == 1)
        #expect(filtered[0].number == 1)
    }

    @Test("nil state filter returns all PRs (no filtering)")
    func noFilterReturnsAll() {
        let prs = [
            GitHubPullRequest(number: 1, title: "Open", state: "open"),
            GitHubPullRequest(number: 2, title: "Draft", state: "open", isDraft: true),
            GitHubPullRequest(number: 3, title: "Closed", state: "closed"),
            GitHubPullRequest(number: 4, title: "Merged", state: "closed", mergedAt: "2025-01-01T00:00:00Z"),
        ]
        let state: PRState? = nil
        let filtered: [GitHubPullRequest]
        if let state {
            filtered = prs.filter { $0.enhancedState == state }
        } else {
            filtered = prs
        }
        #expect(filtered.count == 4)
    }

    // MARK: - displayName

    @Test("displayName returns human-readable names")
    func displayNames() {
        #expect(PRState.open.displayName == "Open")
        #expect(PRState.closed.displayName == "Closed")
        #expect(PRState.merged.displayName == "Merged")
        #expect(PRState.draft.displayName == "Draft")
    }

    // MARK: - Raw values

    @Test("raw values are uppercase")
    func rawValues() {
        #expect(PRState.open.rawValue == "OPEN")
        #expect(PRState.closed.rawValue == "CLOSED")
        #expect(PRState.merged.rawValue == "MERGED")
        #expect(PRState.draft.rawValue == "DRAFT")
    }
}
