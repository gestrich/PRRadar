import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct EvaluateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evaluate",
        abstract: "Run rule evaluations against code (Phase 3)"
    )

    @OptionGroup var options: CLIOptions

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
            case .log(let text):
                if !options.json { print(text, terminator: "") }
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
