import ArgumentParser
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK

struct AnalyzeAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze-all",
        abstract: "Analyze all PRs created since a given date"
    )

    @Option(name: .long, help: "Date in YYYY-MM-DD format")
    var since: String

    @Option(name: .long, help: "Named configuration from settings")
    var config: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Option(name: .long, help: "Path to rules directory")
    var rulesDir: String?

    @Flag(name: .long, help: "Use GitHub diff instead of local")
    var githubDiff: Bool = false

    @Option(name: .long, help: "Minimum violation score")
    var minScore: String?

    @Option(name: .long, help: "GitHub repo (owner/name)")
    var repo: String?

    @Flag(name: .long, help: "Post comments to GitHub (default: dry-run)")
    var comment: Bool = false

    @Option(name: .long, help: "Maximum number of PRs to process")
    var limit: String?

    @Option(name: .long, help: "PR state filter (open, closed, merged, all)")
    var state: String?

    func run() async throws {
        let resolved = try resolveConfig(
            configName: config,
            repoPath: repoPath,
            outputDir: outputDir
        )
        let prRadarConfig = resolved.config
        let environment = resolveEnvironment(config: prRadarConfig)
        let effectiveRulesDir = rulesDir ?? resolved.rulesDir

        let runner = PRRadarCLIRunner()
        let command = PRRadar.Agent.AnalyzeAll(
            since: since,
            rulesDir: effectiveRulesDir,
            repoPath: repoPath,
            githubDiff: githubDiff,
            minScore: minScore,
            repo: repo,
            comment: comment,
            limit: limit,
            state: state
        )

        let result = try await runner.execute(
            command: command,
            config: prRadarConfig,
            environment: environment
        )

        if !result.isSuccess {
            throw CLIError.phaseFailed("analyze-all failed (exit code \(result.exitCode))")
        }
    }
}
