import EnvironmentSDK
import Foundation

public struct RepositoryConfiguration: Sendable {
    public let id: UUID
    public let name: String
    public let repoPath: String
    public let outputDir: String
    public let rulesDir: String
    public let agentScriptPath: String
    public let githubAccount: String
    public let diffSource: DiffSource

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        outputDir: String,
        rulesDir: String,
        agentScriptPath: String,
        githubAccount: String,
        diffSource: DiffSource = .git
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.rulesDir = rulesDir
        self.agentScriptPath = agentScriptPath
        self.githubAccount = githubAccount
        self.diffSource = diffSource
    }

    public init(from json: RepositoryConfigurationJSON, agentScriptPath: String, outputDir: String, repoPathOverride: String? = nil, outputDirOverride: String? = nil, diffSourceOverride: DiffSource? = nil) {
        self.id = json.id
        self.name = json.name
        self.repoPath = repoPathOverride ?? json.repoPath
        self.outputDir = outputDirOverride ?? outputDir
        self.rulesDir = json.rulesDir
        self.agentScriptPath = agentScriptPath
        self.githubAccount = json.githubAccount
        self.diffSource = diffSourceOverride ?? json.diffSource
    }

    public static var defaultRulesDir: String {
        "code-review-rules"
    }

    public var resolvedRulesDir: String {
        PathUtilities.resolve(rulesDir, relativeTo: repoPath)
    }

    public var resolvedOutputDir: String {
        PathUtilities.resolve(outputDir, relativeTo: repoPath)
    }

    public func prDataDirectory(for prNumber: Int) -> String {
        "\(resolvedOutputDir)/\(prNumber)"
    }
}
