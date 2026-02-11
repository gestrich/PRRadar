import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Run the full review pipeline (all phases)"
    )

    @OptionGroup var options: CLIOptions

    @Option(name: .long, help: "Path to rules directory")
    var rulesDir: String?

    @Flag(name: .long, help: "Post comments without dry-run")
    var noDryRun: Bool = false

    @Option(name: .long, help: "Minimum violation score")
    var minScore: String?

    @Flag(name: .long, help: "Suppress AI output (show only status logs)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show full AI output including tool use events")
    var verbose: Bool = false

    func run() async throws {
        let resolved = try resolveConfigFromOptions(options)
        let config = resolved.config
        let useCase = AnalyzeUseCase(config: config)
        let effectiveRulesDir = rulesDir ?? resolved.rulesDir

        if !options.json {
            print("Running full analysis for PR #\(options.prNumber)...")
        }

        var result: AnalyzePhaseOutput?

        for try await progress in useCase.execute(
            prNumber: options.prNumber,
            rulesDir: effectiveRulesDir,
            repoPath: options.repoPath,
            noDryRun: noDryRun,
            minScore: minScore
        ) {
            switch progress {
            case .running(let phase):
                if !options.json {
                    print("  Running \(phase.rawValue)...")
                }
            case .progress:
                break
            case .log(let text):
                if !options.json { print(text, terminator: "") }
            case .aiOutput(let text):
                if !options.json && !quiet {
                    printAIOutput(text, verbose: verbose)
                }
            case .aiPrompt: break
            case .aiToolUse(let name):
                if !options.json && !quiet && verbose {
                    printAIToolUse(name)
                }
            case .evaluationResult: break
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printError(logs)
                }
                throw CLIError.phaseFailed("Analyze failed: \(error)")
            }
        }

        guard let output = result else {
            throw CLIError.phaseFailed("Analyze pipeline produced no output")
        }

        if options.json {
            var jsonOutput: [String: [String]] = [:]
            for (phase, files) in output.files {
                jsonOutput[phase.rawValue] = files
            }
            let data = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\nAnalysis complete:")
            for phase in PRRadarPhase.allCases {
                if let files = output.files[phase] {
                    print("  \(phase.rawValue): \(files.count) files")
                }
            }
        }
    }
}
