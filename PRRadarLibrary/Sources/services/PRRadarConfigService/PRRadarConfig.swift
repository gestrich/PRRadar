import Foundation

public struct RepositoryConfiguration: Sendable {
    public let id: UUID
    public let name: String
    public let repoPath: String
    public let outputDir: String
    public let rulesDir: String
    public let agentScriptPath: String
    public let githubAccount: String

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        outputDir: String,
        rulesDir: String,
        agentScriptPath: String,
        githubAccount: String
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.rulesDir = rulesDir
        self.agentScriptPath = agentScriptPath
        self.githubAccount = githubAccount
    }

    public init(from json: RepositoryConfigurationJSON, agentScriptPath: String, repoPathOverride: String? = nil, outputDirOverride: String? = nil) {
        self.id = json.id
        self.name = json.name
        self.repoPath = repoPathOverride ?? json.repoPath
        self.outputDir = outputDirOverride ?? json.outputDir
        self.rulesDir = json.rulesDir
        self.agentScriptPath = agentScriptPath
        self.githubAccount = json.githubAccount
    }

    public var resolvedOutputDir: String {
        outputDir.isEmpty ? "code-reviews" : outputDir
    }

    public var absoluteOutputDir: String {
        let expanded = NSString(string: resolvedOutputDir).expandingTildeInPath
        if NSString(string: expanded).isAbsolutePath {
            return expanded
        }
        return "\(repoPath)/\(expanded)"
    }

    public func prDataDirectory(for prNumber: Int) -> String {
        "\(absoluteOutputDir)/\(prNumber)"
    }
}
