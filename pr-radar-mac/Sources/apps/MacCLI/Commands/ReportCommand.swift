import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Generate summary report (Phase 4)"
    )

    @Argument(help: "Pull request number")
    var prNumber: String

    @Option(name: .long, help: "Minimum violation score to include")
    var minScore: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false

    func run() async throws {
        let config = resolveConfig(repoPath: repoPath, outputDir: outputDir)
        let environment = resolveEnvironment(config: config)
        let useCase = GenerateReportUseCase(config: config, environment: environment)

        if !json {
            print("Generating report for PR #\(prNumber)...")
        }

        var result: ReportPhaseOutput?

        for try await progress in useCase.execute(prNumber: prNumber, minScore: minScore) {
            switch progress {
            case .running:
                break
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printError(logs)
                }
                throw CLIError.phaseFailed("Report failed: \(error)")
            }
        }

        guard let output = result else {
            throw CLIError.phaseFailed("Report phase produced no output")
        }

        if json {
            let data = try JSONEncoder.prettyEncoder.encode(output.report)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print(output.markdownContent)
        }
    }
}
