import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

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

    @Option(name: .long, help: "Minimum violation score")
    var minScore: String?

    @Option(name: .long, help: "GitHub repo (owner/name)")
    var repo: String?

    @Flag(name: .long, help: "Post comments to GitHub (default: dry-run)")
    var comment: Bool = false

    @Option(name: .long, help: "Maximum number of PRs to process")
    var limit: String?

    @Option(name: .long, help: "PR state filter (open, draft, closed, merged, all). Default: all")
    var state: String?

    @Option(name: .long, help: "GitHub personal access token (overrides GITHUB_TOKEN env var and config)")
    var githubToken: String?

    func run() async throws {
        let stateFilter: PRState? = try parseStateFilter(state)

        let resolved = try resolveConfig(
            configName: config,
            repoPath: repoPath,
            outputDir: outputDir,
            githubToken: githubToken
        )
        let prRadarConfig = resolved.config
        let effectiveRulesDir = rulesDir ?? resolved.rulesDir

        let useCase = AnalyzeAllUseCase(config: prRadarConfig)

        for try await progress in useCase.execute(
            since: since,
            rulesDir: effectiveRulesDir,
            minScore: minScore,
            repo: repo,
            comment: comment,
            limit: limit,
            state: stateFilter
        ) {
            switch progress {
            case .running:
                break
            case .progress:
                break
            case .log(let text):
                print(text, terminator: "")
            case .completed(let output):
                print("\nAnalyze-all complete: \(output.analyzedCount) succeeded, \(output.failedCount) failed")
            case .failed(let error, let logs):
                if !logs.isEmpty { printError(logs) }
                throw CLIError.phaseFailed("analyze-all failed: \(error)")
            }
        }
    }
}
