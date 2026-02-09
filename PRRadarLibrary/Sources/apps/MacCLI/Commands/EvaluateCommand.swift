import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct EvaluateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evaluate",
        abstract: "Run rule evaluations against code (Phase 3)"
    )

    @OptionGroup var options: CLIOptions

    @Flag(name: .long, help: "Suppress AI output (show only status logs)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show full AI output including tool use events")
    var verbose: Bool = false

    func run() async throws {
        let resolved = try resolveConfigFromOptions(options)
        let config = resolved.config
        let useCase = EvaluateUseCase(config: config)

        if !options.json {
            print("Running evaluations for PR #\(options.prNumber)...")
        }

        var result: EvaluationPhaseOutput?

        for try await progress in useCase.execute(prNumber: options.prNumber, repoPath: options.repoPath) {
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
            case .aiToolUse(let name):
                if !options.json && !quiet && verbose {
                    printAIToolUse(name)
                }
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printError(logs)
                }
                throw CLIError.phaseFailed("Evaluate failed: \(error)")
            }
        }

        guard let output = result else {
            throw CLIError.phaseFailed("Evaluate phase produced no output")
        }

        if options.json {
            let data = try JSONEncoder.prettyEncoder.encode(output.summary)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\nEvaluation complete:")
            print("  Total tasks: \(output.summary.totalTasks)")
            print("  Violations found: \(output.summary.violationsFound)")
            print("  Cost: $\(String(format: "%.4f", output.summary.totalCostUsd))")
            let models = output.summary.modelsUsed
            if !models.isEmpty {
                let modelNames = models.map { displayName(forModelId: $0) }.joined(separator: ", ")
                print("  Model: \(modelNames)")
            }
            print("  Duration: \(output.summary.totalDurationMs)ms")

            let violations = output.evaluations.filter { $0.evaluation.violatesRule }
            if !violations.isEmpty {
                print("\nViolations:")
                for eval in violations.sorted(by: { $0.evaluation.score > $1.evaluation.score }) {
                    let score = eval.evaluation.score
                    let color = severityColor(score)
                    print("  \(color)[\(score)/10]\u{001B}[0m \(eval.ruleName)")
                    print("    \(eval.filePath):\(eval.evaluation.lineNumber ?? 0)")
                    print("    \(eval.evaluation.comment)")
                }
            }
        }
    }
}
