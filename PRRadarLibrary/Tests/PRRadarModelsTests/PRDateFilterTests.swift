import Testing
import Foundation
@testable import PRRadarModels

@Suite("PRDateFilter Behavior")
struct PRDateFilterTests {

    let referenceDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14

    // MARK: - date

    @Test("date extracts associated Date for all cases")
    func dateExtractsValue() {
        #expect(PRDateFilter.createdSince(referenceDate).date == referenceDate)
        #expect(PRDateFilter.updatedSince(referenceDate).date == referenceDate)
        #expect(PRDateFilter.mergedSince(referenceDate).date == referenceDate)
        #expect(PRDateFilter.closedSince(referenceDate).date == referenceDate)
    }

    // MARK: - fieldLabel

    @Test("fieldLabel returns correct label for createdSince")
    func fieldLabelCreated() {
        #expect(PRDateFilter.createdSince(referenceDate).fieldLabel == "created")
    }

    @Test("fieldLabel returns correct label for updatedSince")
    func fieldLabelUpdated() {
        #expect(PRDateFilter.updatedSince(referenceDate).fieldLabel == "updated")
    }

    @Test("fieldLabel returns correct label for mergedSince")
    func fieldLabelMerged() {
        #expect(PRDateFilter.mergedSince(referenceDate).fieldLabel == "merged")
    }

    @Test("fieldLabel returns correct label for closedSince")
    func fieldLabelClosed() {
        #expect(PRDateFilter.closedSince(referenceDate).fieldLabel == "closed")
    }

    // MARK: - sortsByCreated

    @Test("sortsByCreated is true only for createdSince")
    func sortsByCreated() {
        #expect(PRDateFilter.createdSince(referenceDate).sortsByCreated == true)
        #expect(PRDateFilter.updatedSince(referenceDate).sortsByCreated == false)
        #expect(PRDateFilter.mergedSince(referenceDate).sortsByCreated == false)
        #expect(PRDateFilter.closedSince(referenceDate).sortsByCreated == false)
    }

    // MARK: - requiresClosedAPIState

    @Test("requiresClosedAPIState is true only for mergedSince and closedSince")
    func requiresClosedAPIState() {
        #expect(PRDateFilter.createdSince(referenceDate).requiresClosedAPIState == false)
        #expect(PRDateFilter.updatedSince(referenceDate).requiresClosedAPIState == false)
        #expect(PRDateFilter.mergedSince(referenceDate).requiresClosedAPIState == true)
        #expect(PRDateFilter.closedSince(referenceDate).requiresClosedAPIState == true)
    }

    // MARK: - dateExtractor

    @Test("dateExtractor returns createdAt for createdSince")
    func dateExtractorCreated() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 1, title: "Test",
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-02T00:00:00Z",
            mergedAt: "2025-01-03T00:00:00Z",
            closedAt: "2025-01-04T00:00:00Z"
        )

        // Act
        let result = PRDateFilter.createdSince(referenceDate).dateExtractor(pr)

        // Assert
        #expect(result == "2025-01-01T00:00:00Z")
    }

    @Test("dateExtractor returns updatedAt for updatedSince")
    func dateExtractorUpdated() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 1, title: "Test",
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-02T00:00:00Z"
        )

        // Act
        let result = PRDateFilter.updatedSince(referenceDate).dateExtractor(pr)

        // Assert
        #expect(result == "2025-01-02T00:00:00Z")
    }

    @Test("dateExtractor returns mergedAt for mergedSince")
    func dateExtractorMerged() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 1, title: "Test",
            mergedAt: "2025-01-03T00:00:00Z"
        )

        // Act
        let result = PRDateFilter.mergedSince(referenceDate).dateExtractor(pr)

        // Assert
        #expect(result == "2025-01-03T00:00:00Z")
    }

    @Test("dateExtractor returns closedAt for closedSince")
    func dateExtractorClosed() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 1, title: "Test",
            closedAt: "2025-01-04T00:00:00Z"
        )

        // Act
        let result = PRDateFilter.closedSince(referenceDate).dateExtractor(pr)

        // Assert
        #expect(result == "2025-01-04T00:00:00Z")
    }

    @Test("dateExtractor returns nil when field is missing")
    func dateExtractorNilField() {
        // Arrange
        let pr = GitHubPullRequest(number: 1, title: "Test")

        // Assert
        #expect(PRDateFilter.mergedSince(referenceDate).dateExtractor(pr) == nil)
        #expect(PRDateFilter.closedSince(referenceDate).dateExtractor(pr) == nil)
    }

    // MARK: - earlyStopExtractor

    @Test("earlyStopExtractor returns createdAt for createdSince")
    func earlyStopCreated() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 1, title: "Test",
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-02T00:00:00Z"
        )

        // Act
        let result = PRDateFilter.createdSince(referenceDate).earlyStopExtractor(pr)

        // Assert
        #expect(result == "2025-01-01T00:00:00Z")
    }

    @Test("earlyStopExtractor returns updatedAt for updatedSince, mergedSince, closedSince")
    func earlyStopUpdatedBased() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 1, title: "Test",
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-02T00:00:00Z"
        )

        // Assert
        #expect(PRDateFilter.updatedSince(referenceDate).earlyStopExtractor(pr) == "2025-01-02T00:00:00Z")
        #expect(PRDateFilter.mergedSince(referenceDate).earlyStopExtractor(pr) == "2025-01-02T00:00:00Z")
        #expect(PRDateFilter.closedSince(referenceDate).earlyStopExtractor(pr) == "2025-01-02T00:00:00Z")
    }
}
