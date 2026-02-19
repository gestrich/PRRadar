import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze code against rules (Phase 3)"
    )

    @OptionGroup var options: CLIOptions

    @Option(name: .long, help: "Filter tasks by file path")
    var file: String?

    @Option(name: .long, help: "Filter tasks by focus area ID")
    var focusArea: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Filter tasks by rule name(s)")
    var rule: [String] = []

    @Flag(name: .long, help: "Suppress AI output (show only status logs)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show full AI output including tool use events")
    var verbose: Bool = false

    func run() async throws {
        let config = try resolveConfigFromOptions(options)

        let filter = AnalysisFilter(
            filePath: file,
            focusAreaId: focusArea,
            ruleNames: rule.isEmpty ? nil : rule
        )

        let stream: AsyncThrowingStream<PhaseProgress<AnalysisOutput>, Error>
        if filter.isEmpty {
            let useCase = AnalyzeUseCase(config: config)
            stream = useCase.execute(prNumber: options.prNumber, repoPath: options.repoPath, commitHash: options.commit)
        } else {
            let useCase = SelectiveAnalyzeUseCase(config: config)
            stream = useCase.execute(prNumber: options.prNumber, filter: filter, repoPath: options.repoPath, commitHash: options.commit)
        }

        if !options.json {
            print("Analyzing PR #\(options.prNumber)...")
        }

        var result: AnalysisOutput?

        for try await progress in stream {
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
            case .analysisResult: break
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
            throw CLIError.phaseFailed("Analyze phase produced no output")
        }

        if options.json {
            let data = try JSONEncoder.prettyEncoder.encode(output.summary)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\nAnalysis complete:")
            let newCount = output.summary.totalTasks - output.cachedCount
            if output.cachedCount > 0 {
                print("  Tasks evaluated: \(newCount) new, \(output.cachedCount) cached, \(output.summary.totalTasks) total")
            } else {
                print("  Total tasks: \(output.summary.totalTasks)")
            }
            print("  Violations found: \(output.summary.violationsFound)")
            print("  Cost: $\(String(format: "%.4f", output.summary.totalCostUsd))")
            let models = output.summary.modelsUsed
            if !models.isEmpty {
                let modelNames = models.map { displayName(forModelId: $0) }.joined(separator: ", ")
                print("  Model: \(modelNames)")
            }
            print("  Duration: \(output.summary.totalDurationMs)ms")

            let violations = output.evaluations.compactMap(\.violation)
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

            let errors = output.evaluations.compactMap(\.error)
            if !errors.isEmpty {
                print("\nErrors:")
                for err in errors {
                    print("  \(err.ruleName) — \(err.filePath)")
                    print("    \(err.errorMessage)")
                }
            }
        }
    }
}
