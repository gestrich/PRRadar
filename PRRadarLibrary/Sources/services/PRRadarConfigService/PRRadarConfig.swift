import Foundation

public struct PRRadarConfig: Sendable {
    public let repoPath: String
    public let outputDir: String
    public let bridgeScriptPath: String
    public let githubToken: String?

    public init(repoPath: String, outputDir: String, bridgeScriptPath: String, githubToken: String? = nil) {
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.bridgeScriptPath = bridgeScriptPath
        self.githubToken = githubToken
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
}
