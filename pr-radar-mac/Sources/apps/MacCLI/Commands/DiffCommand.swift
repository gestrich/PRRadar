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

    @OptionGroup var options: CLIOptions

    @Flag(name: .long, help: "Open output directory in Finder after completion")
    var open: Bool = false

    func run() async throws {
        let resolved = try resolveConfigFromOptions(options)
        let config = resolved.config
        let environment = resolveEnvironment(config: config)
        let useCase = FetchDiffUseCase(config: config, environment: environment)

        if !options.json {
            print("Fetching diff for PR #\(options.prNumber)...")
        }

        var outputFiles: [String] = []

        for try await progress in useCase.execute(prNumber: options.prNumber) {
            switch progress {
            case .running:
                break
            case .completed(let files):
                outputFiles = files
            case .failed(let error, let logs):
                if !logs.isEmpty { printError(logs) }
                throw CLIError.phaseFailed("Diff failed: \(error)")
            }
        }

        if options.json {
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
                prNumber: options.prNumber,
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
