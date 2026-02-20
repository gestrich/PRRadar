import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

@main
struct PRRadarMacCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr-radar-mac",
        abstract: "PRRadar Mac CLI — run review pipeline phases from the terminal",
        subcommands: [
            ConfigCommand.self,
            SyncCommand.self,
            PrepareCommand.self,
            AnalyzeCommand.self,
            ReportCommand.self,
            CommentCommand.self,
            RunCommand.self,
            RunAllCommand.self,
            StatusCommand.self,
            RefreshCommand.self,
            RefreshPRCommand.self,
            TranscriptCommand.self,
        ]
    )
}

struct CLIOptions: ParsableArguments {
    @Argument(help: "Pull request number")
    var prNumber: Int

    @Option(name: .long, help: "Named configuration from settings")
    var config: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Option(name: .long, help: "Commit hash to target (defaults to latest)")
    var commit: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false
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

func resolveAgentScriptPath() -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PRRadarMacCLI.swift → MacCLI/
        .deletingLastPathComponent() // → apps/
        .deletingLastPathComponent() // → Sources/
        .deletingLastPathComponent() // → pr-radar-mac/
        .appendingPathComponent("claude-agent/claude_agent.py")
        .path
}

func resolveConfig(
    configName: String?,
    repoPath: String?,
    outputDir: String?
) throws -> RepositoryConfiguration {
    let settings = LoadSettingsUseCase(settingsService: SettingsService()).execute()
    let targetConfigName = configName ?? settings.configurations.first(where: { $0.isDefault })?.name

    guard let targetConfigName else {
        throw CLIError.configNotFound("No configuration specified and no default configuration found. Use 'config add' to create one.")
    }
    guard let namedConfig = settings.configurations.first(where: { $0.name == targetConfigName }) else {
        throw CLIError.configNotFound(targetConfigName)
    }
    return RepositoryConfiguration(
        from: namedConfig,
        agentScriptPath: resolveAgentScriptPath(),
        outputDir: settings.outputDir,
        repoPathOverride: repoPath,
        outputDirOverride: outputDir
    )
}

func resolveConfigFromOptions(_ options: CLIOptions) throws -> RepositoryConfiguration {
    try resolveConfig(
        configName: options.config,
        repoPath: options.repoPath,
        outputDir: options.outputDir
    )
}

func parseStateFilter(_ value: String?) throws -> PRState? {
    guard let value else { return nil }
    if value.lowercased() == "all" { return nil }
    guard let parsed = PRState.fromCLIString(value) else {
        throw ValidationError("Invalid state '\(value)'. Valid values: open, draft, closed, merged, all")
    }
    return parsed
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func printAIOutput(_ text: String, verbose: Bool) {
    for line in text.components(separatedBy: "\n") {
        if verbose {
            print("    \(line)")
        } else {
            print("    [AI] \(line)")
        }
    }
}

func printAIToolUse(_ name: String) {
    print("    [AI] \u{001B}[36m[tool: \(name)]\u{001B}[0m")
}
