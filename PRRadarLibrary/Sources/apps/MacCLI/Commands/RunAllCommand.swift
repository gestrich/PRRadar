import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct RunAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-all",
        abstract: "Run the full pipeline for all PRs matching a date and state filter"
    )

    @OptionGroup var filterOptions: PRFilterOptions

    @Option(name: .long, help: "Named configuration from settings")
    var config: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Option(name: .long, help: "Rule path name (uses the default rule path if omitted)")
    var rulesPathName: String?

    @Option(name: .long, help: "Minimum violation score")
    var minScore: String?

    @Option(name: .long, help: "GitHub repo (owner/name)")
    var repo: String?

    @Flag(name: .long, help: "Post comments to GitHub (default: dry-run)")
    var comment: Bool = false

    @Option(name: .long, help: "Maximum number of PRs to process")
    var limit: String?

    @Option(name: .long, help: "Diff source: 'git' (local git history) or 'github-api' (GitHub REST API)")
    var diffSource: DiffSource?

    @Option(name: .long, help: "Analysis mode: regex, script, ai, or all (default: all)")
    var mode: AnalysisMode = .all

    @Flag(name: .long, help: "Suppress AI output (show only status logs)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show full AI output including tool use events")
    var verbose: Bool = false

    func run() async throws {
        let prRadarConfig = try resolveConfig(
            configName: config,
            repoPath: repoPath,
            outputDir: outputDir,
            diffSource: diffSource
        )
        let prFilter = try filterOptions.buildFilter()
        guard prFilter.dateFilter != nil else {
            throw ValidationError("A date filter is required. Use --since, --lookback-hours, --updated-since, or --updated-lookback-hours.")
        }

        let useCase = RunAllUseCase(config: prRadarConfig)

        for try await progress in useCase.execute(
            filter: prFilter,
            rulesDir: try resolveRulesDir(rulesPathName: rulesPathName, config: prRadarConfig),
            minScore: minScore,
            repo: repo,
            comment: comment,
            limit: limit,
            analysisMode: mode
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
            case .taskEvent(_, let event):
                switch event {
                case .output(let text):
                    if !quiet {
                        printAIOutput(text, verbose: verbose)
                    }
                case .toolUse(let name):
                    if !quiet && verbose {
                        printAIToolUse(name)
                    }
                case .prompt, .completed:
                    break
                }
            case .completed(let output):
                print("\nRun-all complete: \(output.analyzedCount) succeeded, \(output.failedCount) failed")
            case .failed(let error, let logs):
                if !logs.isEmpty { printError(logs) }
                throw CLIError.phaseFailed("run-all failed: \(error)")
            }
        }
    }
}
