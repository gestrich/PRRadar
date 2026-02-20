import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct RunAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-all",
        abstract: "Run the full pipeline for all PRs created since a given date"
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

    @Flag(name: .long, help: "Suppress AI output (show only status logs)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show full AI output including tool use events")
    var verbose: Bool = false

    func run() async throws {
        let stateFilter: PRState? = try parseStateFilter(state)

        let prRadarConfig = try resolveConfig(
            configName: config,
            repoPath: repoPath,
            outputDir: outputDir
        )
        let useCase = RunAllUseCase(config: prRadarConfig)

        for try await progress in useCase.execute(
            since: since,
            rulesDir: rulesDir ?? prRadarConfig.resolvedRulesDir,
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
            case .prepareOutput(let text):
                if !quiet {
                    printAIOutput(text, verbose: verbose)
                }
            case .prepareToolUse(let name):
                if !quiet && verbose {
                    printAIToolUse(name)
                }
            case .taskOutput(_, let text):
                if !quiet {
                    printAIOutput(text, verbose: verbose)
                }
            case .taskPrompt: break
            case .taskToolUse(_, let name):
                if !quiet && verbose {
                    printAIToolUse(name)
                }
            case .taskCompleted: break
            case .completed(let output):
                print("\nRun-all complete: \(output.analyzedCount) succeeded, \(output.failedCount) failed")
            case .failed(let error, let logs):
                if !logs.isEmpty { printError(logs) }
                throw CLIError.phaseFailed("run-all failed: \(error)")
            }
        }
    }
}
