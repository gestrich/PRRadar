import ArgumentParser
import Foundation
import PRRadarConfigService

@main
struct PRRadarMacCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr-radar-mac",
        abstract: "PRRadar Mac CLI — run review pipeline phases from the terminal",
        subcommands: [
            ConfigCommand.self,
            DiffCommand.self,
            RulesCommand.self,
            EvaluateCommand.self,
            ReportCommand.self,
            CommentCommand.self,
            AnalyzeCommand.self,
            StatusCommand.self,
            RefreshCommand.self,
        ]
    )
}

struct CLIOptions: ParsableArguments {
    @Argument(help: "Pull request number")
    var prNumber: String

    @Option(name: .long, help: "Named configuration from settings")
    var config: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false
}

struct ResolvedConfig {
    let config: PRRadarConfig
    let rulesDir: String?
}

enum CLIError: Error, CustomStringConvertible {
    case missingRepoPath
    case phaseFailed(String)
    case configNotFound(String)

    var description: String {
        switch self {
        case .missingRepoPath:
            return "No repo path specified. Use --repo-path or set a default configuration."
        case .phaseFailed(let message):
            return message
        case .configNotFound(let name):
            return "Configuration '\(name)' not found. Use 'config list' to see available configurations."
        }
    }
}

func resolveConfigFromOptions(_ options: CLIOptions) throws -> ResolvedConfig {
    let venvBinPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PRRadarMacCLI.swift → MacCLI/
        .deletingLastPathComponent() // → apps/
        .deletingLastPathComponent() // → Sources/
        .deletingLastPathComponent() // → pr-radar-mac/
        .deletingLastPathComponent() // → repo root
        .appendingPathComponent(".venv/bin")
        .path

    var repoPath = options.repoPath
    var outputDir = options.outputDir
    var rulesDir: String? = nil

    if let configName = options.config {
        let settings = SettingsService().load()
        guard let namedConfig = settings.configurations.first(where: { $0.name == configName }) else {
            throw CLIError.configNotFound(configName)
        }
        repoPath = repoPath ?? namedConfig.repoPath
        outputDir = outputDir ?? (namedConfig.outputDir.isEmpty ? nil : namedConfig.outputDir)
        rulesDir = namedConfig.rulesDir.isEmpty ? nil : namedConfig.rulesDir
    }

    let config = PRRadarConfig(
        venvBinPath: venvBinPath,
        repoPath: repoPath ?? FileManager.default.currentDirectoryPath,
        outputDir: outputDir ?? "code-reviews"
    )

    return ResolvedConfig(config: config, rulesDir: rulesDir)
}

func resolveEnvironment(config: PRRadarConfig) -> [String: String] {
    PRRadarEnvironment.build(venvBinPath: config.venvBinPath)
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
