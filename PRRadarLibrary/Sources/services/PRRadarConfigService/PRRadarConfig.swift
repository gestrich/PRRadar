import Foundation

// TODO: The name of the this config files is confusing
// I think more accurately this is a RepostioryConfiguration
public struct PRRadarConfig: Sendable {
    public let repoPath: String
    public let outputDir: String
    public let agentScriptPath: String
    public let credentialAccount: String?

    public init(repoPath: String, outputDir: String, agentScriptPath: String, credentialAccount: String? = nil) {
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.agentScriptPath = agentScriptPath
        self.credentialAccount = credentialAccount
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
