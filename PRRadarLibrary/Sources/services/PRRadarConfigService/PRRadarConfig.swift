import Foundation

public struct PRRadarConfig: Sendable {
    public let repoPath: String
    public let outputDir: String
    public let agentScriptPath: String

    public init(repoPath: String, outputDir: String, agentScriptPath: String) {
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.agentScriptPath = agentScriptPath
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
