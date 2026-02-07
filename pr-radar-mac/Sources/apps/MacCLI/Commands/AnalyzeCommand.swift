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

    @Flag(name: .long, help: "Use GitHub diff instead of local")
    var githubDiff: Bool = false

    @Option(name: .long, help: "Stop after this phase (diff, rules, evaluate, report)")
    var stopAfter: String?

    @Option(name: .long, help: "Skip to this phase (rules, evaluate, report, comment)")
    var skipTo: String?

    @Flag(name: .long, help: "Post comments without dry-run")
    var noDryRun: Bool = false

    @Option(name: .long, help: "Minimum violation score")
    var minScore: String?

    @Option(name: .long, help: "GitHub repo (owner/name)")
    var repo: String?

    func run() async throws {
        let resolved = try resolveConfigFromOptions(options)
        let config = resolved.config
        let environment = resolveEnvironment(config: config)
        let useCase = AnalyzeUseCase(config: config, environment: environment)
        let effectiveRulesDir = rulesDir ?? resolved.rulesDir

        if !options.json {
            print("Running full analysis for PR #\(options.prNumber)...")
        }

        var result: AnalyzePhaseOutput?

        for try await progress in useCase.execute(
            prNumber: options.prNumber,
            rulesDir: effectiveRulesDir,
            repoPath: options.repoPath,
            githubDiff: githubDiff,
            stopAfter: stopAfter,
            skipTo: skipTo,
            noDryRun: noDryRun,
            minScore: minScore,
            repo: repo
        ) {
            switch progress {
            case .running(let phase):
                if !options.json {
                    print("  Running \(phase.rawValue)...")
                }
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

            if !output.cliOutput.isEmpty {
                print("\n--- CLI Output ---")
                print(output.cliOutput)
            }
        }
    }
}
