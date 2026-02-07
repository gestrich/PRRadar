import Foundation

public struct PRRadarConfig: Sendable {
    public let venvBinPath: String
    public let repoPath: String
    public let outputDir: String

    public init(venvBinPath: String, repoPath: String, outputDir: String) {
        self.venvBinPath = venvBinPath
        self.repoPath = repoPath
        self.outputDir = outputDir
    }

    public var prradarPath: String {
        "\(venvBinPath)/prradar"
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
