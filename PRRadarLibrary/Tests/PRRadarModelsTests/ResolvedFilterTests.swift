import Foundation
import Testing
@testable import PRRadarConfigService
@testable import PRRadarModels

@Suite("RepositoryConfiguration.makeFilter")
struct MakeFilterTests {

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
        let filter = config.makeFilter()
        #expect(filter.baseBranch == "main")
    }

    @Test("explicit baseBranch overrides config default")
    func explicitBaseBranchOverrides() {
        let filter = config.makeFilter(baseBranch: "develop")
        #expect(filter.baseBranch == "develop")
    }

    @Test("baseBranch 'all' clears filter")
    func baseBranchAllClearsFilter() {
        let filter = config.makeFilter(baseBranch: "all")
        #expect(filter.baseBranch == nil)
    }

    @Test("baseBranch 'ALL' (case insensitive) clears filter")
    func baseBranchAllUppercaseClearsFilter() {
        let filter = config.makeFilter(baseBranch: "ALL")
        #expect(filter.baseBranch == nil)
    }

    @Test("empty baseBranch clears filter")
    func emptyBaseBranchClearsFilter() {
        let filter = config.makeFilter(baseBranch: "")
        #expect(filter.baseBranch == nil)
    }

    // MARK: - State defaulting

    @Test("nil state defaults to .open")
    func nilStateDefaultsToOpen() {
        let filter = config.makeFilter()
        #expect(filter.state == .open)
    }

    @Test("explicit state is preserved")
    func explicitStatePreserved() {
        let filter = config.makeFilter(state: .merged)
        #expect(filter.state == .merged)
    }

    // MARK: - Author passthrough

    @Test("authorLogin passes through unchanged")
    func authorLoginPassthrough() {
        let filter = config.makeFilter(authorLogin: "octocat")
        #expect(filter.authorLogin == "octocat")
    }

    @Test("nil authorLogin stays nil")
    func nilAuthorLoginStaysNil() {
        let filter = config.makeFilter()
        #expect(filter.authorLogin == nil)
    }
}
