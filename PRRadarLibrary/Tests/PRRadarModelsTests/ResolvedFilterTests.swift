import Foundation
import Testing
@testable import PRRadarConfigService
@testable import PRRadarModels

@Suite("RepositoryConfiguration.resolvedFilter")
struct ResolvedFilterTests {

    let config = RepositoryConfiguration(
        name: "test",
        repoPath: "/tmp/repo",
        outputDir: "/tmp/output",
        agentScriptPath: "/tmp/agent.py",
        githubAccount: "owner/repo",
        defaultBaseBranch: "main"
    )

    // MARK: - Base branch defaulting

    @Test("nil baseBranch defaults to config defaultBaseBranch")
    func nilBaseBranchDefaultsToConfig() {
        // Arrange
        let filter = PRFilter()

        // Act
        let resolved = config.resolvedFilter(filter)

        // Assert
        #expect(resolved.baseBranch == "main")
    }

    @Test("explicit baseBranch overrides config default")
    func explicitBaseBranchOverrides() {
        // Arrange
        let filter = PRFilter(baseBranch: "develop")

        // Act
        let resolved = config.resolvedFilter(filter)

        // Assert
        #expect(resolved.baseBranch == "develop")
    }

    @Test("baseBranch 'all' clears filter")
    func baseBranchAllClearsFilter() {
        // Arrange
        let filter = PRFilter(baseBranch: "all")

        // Act
        let resolved = config.resolvedFilter(filter)

        // Assert
        #expect(resolved.baseBranch == nil)
    }

    @Test("baseBranch 'ALL' (case insensitive) clears filter")
    func baseBranchAllUppercaseClearsFilter() {
        // Arrange
        let filter = PRFilter(baseBranch: "ALL")

        // Act
        let resolved = config.resolvedFilter(filter)

        // Assert
        #expect(resolved.baseBranch == nil)
    }

    @Test("empty baseBranch clears filter")
    func emptyBaseBranchClearsFilter() {
        // Arrange
        let filter = PRFilter(baseBranch: "")

        // Act
        let resolved = config.resolvedFilter(filter)

        // Assert
        #expect(resolved.baseBranch == nil)
    }

    // MARK: - State defaulting

    @Test("nil state defaults to .open")
    func nilStateDefaultsToOpen() {
        // Arrange
        let filter = PRFilter()

        // Act
        let resolved = config.resolvedFilter(filter)

        // Assert
        #expect(resolved.state == .open)
    }

    @Test("explicit state is preserved")
    func explicitStatePreserved() {
        // Arrange
        let filter = PRFilter(state: .merged)

        // Act
        let resolved = config.resolvedFilter(filter)

        // Assert
        #expect(resolved.state == .merged)
    }

    // MARK: - Author passthrough

    @Test("authorLogin passes through unchanged")
    func authorLoginPassthrough() {
        // Arrange
        let filter = PRFilter(authorLogin: "octocat")

        // Act
        let resolved = config.resolvedFilter(filter)

        // Assert
        #expect(resolved.authorLogin == "octocat")
    }

    @Test("nil authorLogin stays nil")
    func nilAuthorLoginStaysNil() {
        // Arrange
        let filter = PRFilter()

        // Act
        let resolved = config.resolvedFilter(filter)

        // Assert
        #expect(resolved.authorLogin == nil)
    }
}
