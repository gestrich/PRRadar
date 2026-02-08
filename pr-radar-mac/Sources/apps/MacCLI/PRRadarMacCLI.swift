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
            AnalyzeAllCommand.self,
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

    @Option(name: .long, help: "GitHub personal access token (overrides GITHUB_TOKEN env var and config)")
    var githubToken: String?

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

func resolveBridgeScriptPath() -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PRRadarMacCLI.swift → MacCLI/
        .deletingLastPathComponent() // → apps/
        .deletingLastPathComponent() // → Sources/
        .deletingLastPathComponent() // → pr-radar-mac/
        .appendingPathComponent("bridge/claude_bridge.py")
        .path
}

func resolveConfig(
    configName: String?,
    repoPath: String?,
    outputDir: String?,
    githubToken: String? = nil
) throws -> ResolvedConfig {
    var resolvedRepoPath = repoPath
    var resolvedOutputDir = outputDir
    var rulesDir: String? = nil
    var configToken: String? = nil

    let settings = SettingsService().load()
    
    // If no config name specified, use the default config if one exists
    let targetConfigName = configName ?? settings.configurations.first(where: { $0.isDefault })?.name
    
    if let targetConfigName {
        guard let namedConfig = settings.configurations.first(where: { $0.name == targetConfigName }) else {
            throw CLIError.configNotFound(targetConfigName)
        }
        resolvedRepoPath = resolvedRepoPath ?? namedConfig.repoPath
        resolvedOutputDir = resolvedOutputDir ?? (namedConfig.outputDir.isEmpty ? nil : namedConfig.outputDir)
        rulesDir = namedConfig.rulesDir.isEmpty ? nil : namedConfig.rulesDir
        configToken = namedConfig.githubToken
    }

    // Token priority: CLI flag > env var > per-repo config
    let resolvedToken = githubToken
        ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
        ?? configToken

    let config = PRRadarConfig(
        repoPath: resolvedRepoPath ?? FileManager.default.currentDirectoryPath,
        outputDir: resolvedOutputDir ?? "code-reviews",
        bridgeScriptPath: resolveBridgeScriptPath(),
        githubToken: resolvedToken
    )

    return ResolvedConfig(config: config, rulesDir: rulesDir)
}

func resolveConfigFromOptions(_ options: CLIOptions) throws -> ResolvedConfig {
    try resolveConfig(
        configName: options.config,
        repoPath: options.repoPath,
        outputDir: options.outputDir,
        githubToken: options.githubToken
    )
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
