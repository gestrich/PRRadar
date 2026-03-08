import ArgumentParser
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct OutputCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "output",
        abstract: "View saved evaluation output for a PR"
    )

    @OptionGroup var options: CLIOptions

    @Option(name: .long, help: "Filter by phase (prepare, evaluate)")
    var phase: String?

    @Option(name: .long, help: "Display a specific task's output by identifier")
    var task: String?

    @Flag(name: .long, help: "Output raw JSON")
    var jsonOutput: Bool = false

    @Flag(name: .long, help: "Output rendered markdown (default for terminal)")
    var markdown: Bool = false

    func run() async throws {
        let config = try resolveConfigFromOptions(options)
        let commitHash = options.commit ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: options.prNumber)

        let phasesToCheck: [PRRadarPhase]
        if let phaseStr = phase {
            guard let matched = PRRadarPhase.allCases.first(where: { $0.rawValue == phaseStr }) else {
                throw CLIError.phaseFailed("Unknown phase '\(phaseStr)'. Valid: prepare, evaluate")
            }
            phasesToCheck = [matched]
        } else {
            phasesToCheck = [.prepare, .analyze]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var allOutputs: [(phase: PRRadarPhase, output: EvaluationOutput)] = []

        for p in phasesToCheck {
            let files = PhaseOutputParser.listPhaseFiles(
                config: config, prNumber: options.prNumber, phase: p, commitHash: commitHash
            )
            let outputFiles = files.filter { $0.hasPrefix("output-") && $0.hasSuffix(".json") }

            for filename in outputFiles {
                guard let data = try? PhaseOutputParser.readPhaseFile(
                    config: config, prNumber: options.prNumber, phase: p, filename: filename, commitHash: commitHash
                ),
                      let output = try? decoder.decode(EvaluationOutput.self, from: data)
                else { continue }

                allOutputs.append((phase: p, output: output))
            }
        }

        if allOutputs.isEmpty {
            if options.json || jsonOutput {
                print("[]")
            } else {
                print("No evaluation output found for PR #\(options.prNumber).")
            }
            return
        }

        if let taskId = task {
            guard let match = allOutputs.first(where: { $0.output.identifier == taskId }) else {
                throw CLIError.phaseFailed("No output found with identifier '\(taskId)'")
            }
            printOutput(match.output, phase: match.phase)
            return
        }

        if options.json || jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let outputObjects = allOutputs.map(\.output)
            let data = try encoder.encode(outputObjects)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Evaluation output for PR #\(options.prNumber):\n")
            for (p, output) in allOutputs {
                let mode = output.mode.rawValue.uppercased()
                let duration = "\(output.durationMs)ms"
                var details = "[\(p.displayName)] \(output.identifier)  \(mode)  \(duration)"
                if let model = aiModelName(for: output) {
                    details += "  \(model)"
                }
                if output.costUsd > 0 {
                    details += "  \(String(format: "$%.4f", output.costUsd))"
                }
                print("  \(details)")
            }
            print("\nUse --task <identifier> to view a specific output.")
        }
    }

    private func printOutput(_ output: EvaluationOutput, phase: PRRadarPhase) {
        if options.json || jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(output) {
                print(String(data: data, encoding: .utf8)!)
            }
        } else {
            print(EvaluationOutputWriter.renderMarkdown(output))
        }
    }

    private func aiModelName(for output: EvaluationOutput) -> String? {
        if case .ai(let model, _) = output.source {
            return displayName(forModelId: model)
        }
        return nil
    }
}
