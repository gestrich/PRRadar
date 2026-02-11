import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct PrepareCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prepare",
        abstract: "Prepare evaluation tasks (Phase 2)"
    )

    @OptionGroup var options: CLIOptions

    @Option(name: .long, help: "Path to rules directory")
    var rulesDir: String?

    @Flag(name: .long, help: "Suppress AI output (show only status logs)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show full AI output including tool use events")
    var verbose: Bool = false

    func run() async throws {
        let resolved = try resolveConfigFromOptions(options)
        let config = resolved.config
        let useCase = PrepareUseCase(config: config)
        let effectiveRulesDir = rulesDir ?? resolved.rulesDir

        if !options.json {
            print("Preparing evaluation tasks for PR #\(options.prNumber)...")
        }

        var result: PrepareOutput?

        for try await progress in useCase.execute(prNumber: options.prNumber, rulesDir: effectiveRulesDir) {
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
                throw CLIError.phaseFailed("Prepare failed: \(error)")
            }
        }

        guard let output = result else {
            throw CLIError.phaseFailed("Prepare phase produced no output")
        }

        if options.json {
            let jsonOutput: [String: Any] = [
                "focus_areas": output.focusAreas.count,
                "rules": output.rules.count,
                "tasks": output.tasks.count,
            ]
            let data = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\nPrepare complete:")
            print("  Focus areas: \(output.focusAreas.count)")
            print("  Rules loaded: \(output.rules.count)")
            print("  Evaluation tasks: \(output.tasks.count)")

            if !output.focusAreas.isEmpty {
                print("\nFocus areas:")
                for area in output.focusAreas {
                    print("  [\(area.focusType.rawValue)] \(area.filePath):\(area.startLine)-\(area.endLine)")
                    print("    \(area.description)")
                }
            }

            if !output.rules.isEmpty {
                print("\nRules:")
                for rule in output.rules {
                    print("  [\(rule.category)] \(rule.name)")
                }
            }
        }
    }
}
