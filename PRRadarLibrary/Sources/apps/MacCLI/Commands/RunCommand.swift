import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
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
        let config = try resolveConfigFromOptions(options)
        let useCase = RunPipelineUseCase(config: config)
        if !options.json {
            print("Running full pipeline for PR #\(options.prNumber)...")
        }

        var result: RunPipelineOutput?

        for try await progress in useCase.execute(
            prNumber: options.prNumber,
            rulesDir: rulesDir ?? config.resolvedRulesDir,
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
            case .taskOutput(let text):
                if !options.json && !quiet {
                    printAIOutput(text, verbose: verbose)
                }
            case .taskPrompt: break
            case .taskToolUse(let name):
                if !options.json && !quiet && verbose {
                    printAIToolUse(name)
                }
            case .taskCompleted: break
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printError(logs)
                }
                throw CLIError.phaseFailed("Run failed: \(error)")
            }
        }

        guard let output = result else {
            throw CLIError.phaseFailed("Run pipeline produced no output")
        }

        if options.json {
            var jsonOutput: [String: [String]] = [:]
            for (phase, files) in output.files {
                jsonOutput[phase.rawValue] = files
            }
            let data = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\nPipeline complete:")
            for phase in PRRadarPhase.allCases {
                if let files = output.files[phase] {
                    print("  \(phase.rawValue): \(files.count) files")
                }
            }
        }
    }
}
