import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct RulesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rules",
        abstract: "Generate focus areas, load rules, and create evaluation tasks (Phase 2)"
    )

    @Argument(help: "Pull request number")
    var prNumber: String

    @Option(name: .long, help: "Path to rules directory")
    var rulesDir: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false

    func run() async throws {
        let config = resolveConfig(repoPath: repoPath, outputDir: outputDir)
        let environment = resolveEnvironment(config: config)
        let useCase = FetchRulesUseCase(config: config, environment: environment)

        if !json {
            print("Running rules phase for PR #\(prNumber)...")
        }

        var result: RulesPhaseOutput?

        for try await progress in useCase.execute(prNumber: prNumber, rulesDir: rulesDir) {
            switch progress {
            case .running(let phase):
                if !json {
                    print("  Running \(phase.rawValue)...")
                }
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printError(logs)
                }
                throw CLIError.phaseFailed("Rules failed: \(error)")
            }
        }

        guard let output = result else {
            throw CLIError.phaseFailed("Rules phase produced no output")
        }

        if json {
            let jsonOutput: [String: Any] = [
                "focus_areas": output.focusAreas.count,
                "rules": output.rules.count,
                "tasks": output.tasks.count,
            ]
            let data = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\nRules phase complete:")
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
