import ArgumentParser
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct EffectiveDiffCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "effective-diff",
        abstract: "Show the effective diff for a PR (moves stripped, only real changes)"
    )

    @OptionGroup var options: CLIOptions

    func run() async throws {
        let config = try resolveConfigFromOptions(options)
        let commitHash = options.commit ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: options.prNumber)

        guard let diff = PhaseOutputParser.loadEffectiveDiff(config: config, prNumber: options.prNumber, commitHash: commitHash) else {
            printError("No effective diff found for PR #\(options.prNumber). Run 'sync' first.")
            throw ExitCode.failure
        }

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(diff)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Effective diff for PR #\(options.prNumber)\(commitHash.map { " @ \($0)" } ?? ""):\n")
            for hunk in diff.hunks {
                print(hunk.content)
            }
        }
    }
}
