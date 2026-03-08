import Testing
import Foundation
@testable import PRRadarModels

@Suite("PRFilter Behavior")
struct PRFilterTests {

    let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Composition

    @Test("PRFilter composes dateFilter and state")
    func composesDateFilterAndState() {
        // Arrange
        let filter = PRFilter(dateFilter: .updatedSince(referenceDate), state: .open)

        // Assert
        #expect(filter.dateFilter?.fieldLabel == "updated")
        #expect(filter.state == .open)
    }

    @Test("PRFilter with nil dateFilter has no date constraint")
    func nilDateFilter() {
        // Arrange
        let filter = PRFilter(state: .merged)

        // Assert
        #expect(filter.dateFilter == nil)
        #expect(filter.state == .merged)
    }

    @Test("PRFilter with nil state has no state constraint")
    func nilState() {
        // Arrange
        let filter = PRFilter(dateFilter: .createdSince(referenceDate))

        // Assert
        #expect(filter.dateFilter != nil)
        #expect(filter.state == nil)
    }

    @Test("PRFilter default init has no constraints")
    func defaultInit() {
        // Arrange
        let filter = PRFilter()

        // Assert
        #expect(filter.dateFilter == nil)
        #expect(filter.state == nil)
    }

    // MARK: - Date filtering on PR arrays

    @Test("createdSince filters PRs by createdAt date")
    func createdSinceFilters() {
        // Arrange
        let formatter = ISO8601DateFormatter()
        let cutoff = formatter.date(from: "2025-01-15T00:00:00Z")!
        let dateFilter = PRDateFilter.createdSince(cutoff)
        let prs = [
            GitHubPullRequest(number: 1, title: "Old", createdAt: "2025-01-10T00:00:00Z"),
            GitHubPullRequest(number: 2, title: "New", createdAt: "2025-01-20T00:00:00Z"),
            GitHubPullRequest(number: 3, title: "Exact", createdAt: "2025-01-15T00:00:00Z"),
        ]

        // Act
        let filtered = prs.filter { pr in
            guard let dateStr = dateFilter.extractDate(pr),
                  let date = formatter.date(from: dateStr) else { return false }
            return date >= cutoff
        }

        // Assert
        #expect(filtered.count == 2)
        #expect(filtered.map(\.number) == [2, 3])
    }

    @Test("updatedSince filters PRs by updatedAt date")
    func updatedSinceFilters() {
        // Arrange
        let formatter = ISO8601DateFormatter()
        let cutoff = formatter.date(from: "2025-01-15T00:00:00Z")!
        let dateFilter = PRDateFilter.updatedSince(cutoff)
        let prs = [
            GitHubPullRequest(number: 1, title: "Old created, recently updated",
                              createdAt: "2025-01-01T00:00:00Z", updatedAt: "2025-01-20T00:00:00Z"),
            GitHubPullRequest(number: 2, title: "New created, not updated",
                              createdAt: "2025-01-20T00:00:00Z", updatedAt: "2025-01-10T00:00:00Z"),
        ]

        // Act
        let filtered = prs.filter { pr in
            guard let dateStr = dateFilter.extractDate(pr),
                  let date = formatter.date(from: dateStr) else { return false }
            return date >= cutoff
        }

        // Assert
        #expect(filtered.count == 1)
        #expect(filtered[0].number == 1)
    }

    @Test("mergedSince filters PRs by mergedAt date")
    func mergedSinceFilters() {
        // Arrange
        let formatter = ISO8601DateFormatter()
        let cutoff = formatter.date(from: "2025-01-15T00:00:00Z")!
        let dateFilter = PRDateFilter.mergedSince(cutoff)
        let prs = [
            GitHubPullRequest(number: 1, title: "Merged before cutoff",
                              mergedAt: "2025-01-10T00:00:00Z"),
            GitHubPullRequest(number: 2, title: "Merged after cutoff",
                              mergedAt: "2025-01-20T00:00:00Z"),
            GitHubPullRequest(number: 3, title: "Not merged"),
        ]

        // Act
        let filtered = prs.filter { pr in
            guard let dateStr = dateFilter.extractDate(pr),
                  let date = formatter.date(from: dateStr) else { return false }
            return date >= cutoff
        }

        // Assert
        #expect(filtered.count == 1)
        #expect(filtered[0].number == 2)
    }

    // MARK: - State post-filtering composes with date filter

    @Test("updatedSince + state .open excludes merged PRs")
    func updatedSinceWithOpenState() {
        // Arrange
        let prs = [
            GitHubPullRequest(number: 1, title: "Open PR", state: "open",
                              updatedAt: "2025-01-20T00:00:00Z"),
            GitHubPullRequest(number: 2, title: "Merged PR", state: "closed",
                              updatedAt: "2025-01-20T00:00:00Z", mergedAt: "2025-01-20T00:00:00Z"),
            GitHubPullRequest(number: 3, title: "Draft PR", state: "open", isDraft: true,
                              updatedAt: "2025-01-20T00:00:00Z"),
        ]
        let stateFilter: PRState = .open

        // Act
        let filtered = prs.filter { $0.enhancedState == stateFilter }

        // Assert
        #expect(filtered.count == 1)
        #expect(filtered[0].number == 1)
    }

    @Test("closedSince requires closed API state")
    func closedSinceAPIState() {
        // Arrange
        let filter = PRFilter(dateFilter: .closedSince(referenceDate), state: .closed)

        // Assert
        #expect(filter.dateFilter?.requiresClosedAPIState == true)
    }

    // MARK: - Base branch filtering

    @Test("PRFilter stores baseBranch")
    func baseBranchFilter() {
        // Arrange
        let filter = PRFilter(state: .open, baseBranch: "main")

        // Assert
        #expect(filter.baseBranch == "main")
    }

    @Test("PRFilter with nil baseBranch has no branch constraint")
    func nilBaseBranch() {
        // Arrange
        let filter = PRFilter(state: .open)

        // Assert
        #expect(filter.baseBranch == nil)
    }

    // MARK: - Author filtering

    @Test("PRFilter stores authorLogin")
    func authorLoginFilter() {
        // Arrange
        let filter = PRFilter(authorLogin: "octocat")

        // Assert
        #expect(filter.authorLogin == "octocat")
    }

    @Test("PRFilter with nil authorLogin has no author constraint")
    func nilAuthorLogin() {
        // Arrange
        let filter = PRFilter()

        // Assert
        #expect(filter.authorLogin == nil)
    }

    @Test("PRFilter composes all fields together")
    func composesAllFields() {
        // Arrange
        let filter = PRFilter(
            dateFilter: .createdSince(referenceDate),
            state: .open,
            baseBranch: "develop",
            authorLogin: "dev-user"
        )

        // Assert
        #expect(filter.dateFilter != nil)
        #expect(filter.state == .open)
        #expect(filter.baseBranch == "develop")
        #expect(filter.authorLogin == "dev-user")
    }

    // MARK: - Early stop behavior

    @Test("early stop uses createdAt for createdSince")
    func earlyStopCreatedSince() {
        // Arrange
        let formatter = ISO8601DateFormatter()
        let cutoff = formatter.date(from: "2025-01-15T00:00:00Z")!
        let dateFilter = PRDateFilter.createdSince(cutoff)
        let oldPR = GitHubPullRequest(
            number: 1, title: "Old",
            createdAt: "2025-01-10T00:00:00Z", updatedAt: "2025-01-20T00:00:00Z"
        )

        // Act
        let earlyStopStr = dateFilter.extractEarlyStopDate(oldPR)
        let earlyStopDate = earlyStopStr.flatMap { formatter.date(from: $0) }
        let shouldStop = earlyStopDate.map { $0 < cutoff } ?? false

        // Assert — stops on createdAt (Jan 10), not updatedAt (Jan 20)
        #expect(shouldStop == true)
    }

    @Test("early stop uses updatedAt for mergedSince")
    func earlyStopMergedSince() {
        // Arrange
        let formatter = ISO8601DateFormatter()
        let cutoff = formatter.date(from: "2025-01-15T00:00:00Z")!
        let dateFilter = PRDateFilter.mergedSince(cutoff)
        let pr = GitHubPullRequest(
            number: 1, title: "Merged before, updated after",
            updatedAt: "2025-01-20T00:00:00Z", mergedAt: "2025-01-10T00:00:00Z"
        )

        // Act
        let earlyStopStr = dateFilter.extractEarlyStopDate(pr)
        let earlyStopDate = earlyStopStr.flatMap { formatter.date(from: $0) }
        let shouldStop = earlyStopDate.map { $0 < cutoff } ?? false

        // Assert — does NOT stop because updatedAt (Jan 20) is after cutoff
        #expect(shouldStop == false)
    }
}
