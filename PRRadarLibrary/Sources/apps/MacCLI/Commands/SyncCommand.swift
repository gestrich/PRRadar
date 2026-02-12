import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync PR data (Phase 1)"
    )

    @OptionGroup var options: CLIOptions

    @Flag(name: .long, help: "Open output directory in Finder after completion")
    var open: Bool = false

    func run() async throws {
        let resolved = try resolveConfigFromOptions(options)
        let config = resolved.config
        let useCase = SyncPRUseCase(config: config)

        if !options.json {
            print("Syncing PR #\(options.prNumber)...")
        }

        var outputFiles: [String] = []
        var commitHash: String?

        for try await progress in useCase.execute(prNumber: options.prNumber) {
            switch progress {
            case .running:
                break
            case .progress:
                break
            case .log(let text):
                if !options.json { print(text, terminator: "") }
            case .aiOutput: break
            case .aiPrompt: break
            case .aiToolUse: break
            case .analysisResult: break
            case .completed(let snapshot):
                outputFiles = snapshot.files
                commitHash = snapshot.commitHash
            case .failed(let error, let logs):
                if !logs.isEmpty { printError(logs) }
                throw CLIError.phaseFailed("Sync failed: \(error)")
            }
        }

        if options.json {
            var jsonDict: [String: Any] = ["files": outputFiles]
            if let commitHash { jsonDict["commitHash"] = commitHash }
            let data = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Sync complete: \(outputFiles.count) files generated")
            if let commitHash {
                print("  Commit: \(commitHash)")
            }
            for file in outputFiles {
                print("  \(file)")
            }
        }

        if `open` {
            let phaseDir = DataPathsService.phaseDirectory(
                outputDir: config.absoluteOutputDir,
                prNumber: options.prNumber,
                phase: .diff,
                commitHash: commitHash
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
