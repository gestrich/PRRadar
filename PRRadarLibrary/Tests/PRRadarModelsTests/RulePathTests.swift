import Testing
import Foundation
@testable import PRRadarConfigService

struct RulePathTests {

    // MARK: - Encoding/Decoding

    @Test func roundTripEncoding() throws {
        // Arrange
        let rulePath = RulePath(name: "shared", path: "/Users/bill/shared-rules", isDefault: true)

        // Act
        let data = try JSONEncoder().encode(rulePath)
        let decoded = try JSONDecoder().decode(RulePath.self, from: data)

        // Assert
        #expect(decoded.id == rulePath.id)
        #expect(decoded.name == "shared")
        #expect(decoded.path == "/Users/bill/shared-rules")
        #expect(decoded.isDefault == true)
    }

    @Test func defaultIsDefaultIsFalse() {
        // Arrange & Act
        let rulePath = RulePath(name: "test", path: "rules")

        // Assert
        #expect(rulePath.isDefault == false)
    }
}

struct RepositoryConfigurationRulePathTests {

    // MARK: - defaultRulePath

    @Test func defaultRulePathReturnsMarkedDefault() {
        // Arrange
        let config = RepositoryConfiguration(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [
                RulePath(name: "shared", path: "/shared/rules", isDefault: false),
                RulePath(name: "local", path: "local-rules", isDefault: true),
            ],
            agentScriptPath: "/tmp/agent.py",
            githubAccount: "test"
        )

        // Act
        let result = config.defaultRulePath

        // Assert
        #expect(result?.name == "local")
    }

    @Test func defaultRulePathFallsBackToFirst() {
        // Arrange
        let config = RepositoryConfiguration(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [
                RulePath(name: "first", path: "first-rules", isDefault: false),
                RulePath(name: "second", path: "second-rules", isDefault: false),
            ],
            agentScriptPath: "/tmp/agent.py",
            githubAccount: "test"
        )

        // Act
        let result = config.defaultRulePath

        // Assert
        #expect(result?.name == "first")
    }

    @Test func defaultRulePathReturnsNilWhenEmpty() {
        // Arrange
        let config = RepositoryConfiguration(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [],
            agentScriptPath: "/tmp/agent.py",
            githubAccount: "test"
        )

        // Act
        let result = config.defaultRulePath

        // Assert
        #expect(result == nil)
    }

    // MARK: - resolvedDefaultRulesDir

    @Test func resolvedDefaultRulesDirWithAbsolutePath() {
        // Arrange
        let config = RepositoryConfiguration(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [RulePath(name: "shared", path: "/Users/bill/shared-rules", isDefault: true)],
            agentScriptPath: "/tmp/agent.py",
            githubAccount: "test"
        )

        // Act
        let result = config.resolvedDefaultRulesDir

        // Assert
        #expect(result == "/Users/bill/shared-rules")
    }

    @Test func resolvedDefaultRulesDirWithRelativePath() {
        // Arrange
        let config = RepositoryConfiguration(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [RulePath(name: "local", path: "code-review-rules", isDefault: true)],
            agentScriptPath: "/tmp/agent.py",
            githubAccount: "test"
        )

        // Act
        let result = config.resolvedDefaultRulesDir

        // Assert
        #expect(result == "/tmp/repo/code-review-rules")
    }

    @Test func resolvedDefaultRulesDirWithTildePath() {
        // Arrange
        let config = RepositoryConfiguration(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [RulePath(name: "home", path: "~/shared-rules", isDefault: true)],
            agentScriptPath: "/tmp/agent.py",
            githubAccount: "test"
        )

        // Act
        let result = config.resolvedDefaultRulesDir

        // Assert
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(result == "\(home)/shared-rules")
    }

    @Test func resolvedDefaultRulesDirReturnsEmptyWhenNoRulePaths() {
        // Arrange
        let config = RepositoryConfiguration(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [],
            agentScriptPath: "/tmp/agent.py",
            githubAccount: "test"
        )

        // Act
        let result = config.resolvedDefaultRulesDir

        // Assert
        #expect(result == "")
    }

    // MARK: - resolvedRulesDir(named:)

    @Test func resolvedRulesDirNamedFindsMatchingPath() {
        // Arrange
        let config = RepositoryConfiguration(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [
                RulePath(name: "shared", path: "/shared/rules", isDefault: true),
                RulePath(name: "local", path: "local-rules", isDefault: false),
            ],
            agentScriptPath: "/tmp/agent.py",
            githubAccount: "test"
        )

        // Act
        let result = config.resolvedRulesDir(named: "local")

        // Assert
        #expect(result == "/tmp/repo/local-rules")
    }

    @Test func resolvedRulesDirNamedReturnsNilForUnknownName() {
        // Arrange
        let config = RepositoryConfiguration(
            name: "test",
            repoPath: "/tmp/repo",
            outputDir: "/tmp/output",
            rulePaths: [RulePath(name: "shared", path: "/shared/rules", isDefault: true)],
            agentScriptPath: "/tmp/agent.py",
            githubAccount: "test"
        )

        // Act
        let result = config.resolvedRulesDir(named: "nonexistent")

        // Assert
        #expect(result == nil)
    }
}
