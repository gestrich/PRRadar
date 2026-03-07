import EnvironmentSDK
import Foundation

public struct RepositoryConfiguration: Sendable {
    public let id: UUID
    public let name: String
    public let repoPath: String
    public let outputDir: String
    public let rulePaths: [RulePath]
    public let agentScriptPath: String
    public let githubAccount: String
    public let diffSource: DiffSource
    public let defaultBaseBranch: String

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        outputDir: String,
        rulePaths: [RulePath] = [],
        agentScriptPath: String,
        githubAccount: String,
        diffSource: DiffSource = .git,
        defaultBaseBranch: String
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.rulePaths = rulePaths
        self.agentScriptPath = agentScriptPath
        self.githubAccount = githubAccount
        self.diffSource = diffSource
        self.defaultBaseBranch = defaultBaseBranch
    }

    public init(from json: RepositoryConfigurationJSON, agentScriptPath: String, outputDir: String, repoPathOverride: String? = nil, outputDirOverride: String? = nil, diffSourceOverride: DiffSource? = nil) {
        self.id = json.id
        self.name = json.name
        self.repoPath = repoPathOverride ?? json.repoPath
        self.outputDir = outputDirOverride ?? outputDir
        self.rulePaths = json.rulePaths
        self.agentScriptPath = agentScriptPath
        self.githubAccount = json.githubAccount
        self.diffSource = diffSourceOverride ?? json.diffSource
        self.defaultBaseBranch = json.defaultBaseBranch
    }

    public static var defaultRulePaths: [RulePath] {
        [RulePath(name: "default", path: "code-review-rules", isDefault: true)]
    }

    public var defaultRulePath: RulePath? {
        rulePaths.first(where: { $0.isDefault }) ?? rulePaths.first
    }

    public var resolvedDefaultRulesDir: String {
        guard let defaultPath = defaultRulePath else { return "" }
        return resolvedRulesDir(for: defaultPath)
    }

    public var allResolvedRulesDirs: [String] {
        rulePaths.map { resolvedRulesDir(for: $0) }
    }

    public func resolvedRulesDir(for rulePath: RulePath) -> String {
        PathUtilities.resolve(rulePath.path, relativeTo: repoPath)
    }

    public func resolvedRulesDir(named name: String) -> String? {
        guard let rulePath = rulePaths.first(where: { $0.name == name }) else {
            return nil
        }
        return resolvedRulesDir(for: rulePath)
    }

    public var resolvedOutputDir: String {
        PathUtilities.resolve(outputDir, relativeTo: repoPath)
    }

    public func prDataDirectory(for prNumber: Int) -> String {
        "\(resolvedOutputDir)/\(prNumber)"
    }
}
