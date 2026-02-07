import ArgumentParser
import Foundation
import PRRadarConfigService

@main
struct PRRadarMacCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr-radar-mac",
        abstract: "PRRadar Mac CLI — run review pipeline phases from the terminal",
        subcommands: [
            DiffCommand.self,
            RulesCommand.self,
            EvaluateCommand.self,
            ReportCommand.self,
            CommentCommand.self,
            AnalyzeCommand.self,
            StatusCommand.self,
        ]
    )
}

struct CLIOptions: ParsableArguments {
    @Argument(help: "Pull request number")
    var prNumber: String

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false
}

enum CLIError: Error, CustomStringConvertible {
    case missingRepoPath
    case phaseFailed(String)

    var description: String {
        switch self {
        case .missingRepoPath:
            return "No repo path specified. Use --repo-path or set a default configuration."
        case .phaseFailed(let message):
            return message
        }
    }
}

func resolveConfig(repoPath: String?, outputDir: String?) -> PRRadarConfig {
    let venvBinPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PRRadarMacCLI.swift → MacCLI/
        .deletingLastPathComponent() // → apps/
        .deletingLastPathComponent() // → Sources/
        .deletingLastPathComponent() // → pr-radar-mac/
        .deletingLastPathComponent() // → repo root
        .appendingPathComponent(".venv/bin")
        .path

    return PRRadarConfig(
        venvBinPath: venvBinPath,
        repoPath: repoPath ?? FileManager.default.currentDirectoryPath,
        outputDir: outputDir ?? "code-reviews"
    )
}

func resolveEnvironment(config: PRRadarConfig) -> [String: String] {
    PRRadarEnvironment.build(venvBinPath: config.venvBinPath)
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
