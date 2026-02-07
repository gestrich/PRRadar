import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct DiffCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Fetch and parse PR diff (Phase 1)"
    )

    @Argument(help: "Pull request number")
    var prNumber: String

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false

    @Flag(name: .long, help: "Open output directory in Finder after completion")
    var open: Bool = false

    func run() async throws {
        let config = resolveConfig(repoPath: repoPath, outputDir: outputDir)
        let environment = resolveEnvironment(config: config)
        let useCase = FetchDiffUseCase(config: config, environment: environment)

        if !json {
            print("Fetching diff for PR #\(prNumber)...")
        }

        var outputFiles: [String] = []

        for try await progress in useCase.execute(prNumber: prNumber) {
            switch progress {
            case .running:
                break
            case .completed(let files):
                outputFiles = files
            case .failed(let error):
                throw CLIError.phaseFailed("Diff failed: \(error)")
            }
        }

        if json {
            let data = try JSONEncoder.prettyEncoder.encode(["files": outputFiles])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Phase 1 complete: \(outputFiles.count) files generated")
            for file in outputFiles {
                print("  \(file)")
            }
        }

        if `open` {
            let phaseDir = DataPathsService.phaseDirectory(
                outputDir: config.absoluteOutputDir,
                prNumber: prNumber,
                phase: .pullRequest
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [phaseDir]
            try process.run()
        }
    }
}

extension JSONEncoder {
    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
