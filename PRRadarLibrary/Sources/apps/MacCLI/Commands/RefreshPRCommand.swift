import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct RefreshPRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refresh-pr",
        abstract: "Re-fetch PR data from GitHub (diff, comments, metadata)"
    )

    @OptionGroup var options: CLIOptions

    func run() async throws {
        let config = try resolveConfigFromOptions(options)
        let useCase = SyncPRUseCase(config: config)

        print("Refreshing PR #\(options.prNumber)...")

        var result: SyncSnapshot?

        for try await progress in useCase.execute(prNumber: options.prNumber) {
            switch progress {
            case .running:
                break
            case .progress:
                break
            case .log(let text):
                print(text, terminator: "")
            case .taskOutput: break
            case .taskPrompt: break
            case .taskToolUse: break
            case .taskCompleted: break
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printError(logs)
                }
                throw CLIError.phaseFailed("Refresh PR failed: \(error)")
            }
        }

        guard let output = result else {
            throw CLIError.phaseFailed("Refresh PR produced no output")
        }

        print("\nRefresh complete:")
        print("  Files written: \(output.files.count)")
        print("  Issue comments: \(output.commentCount)")
        print("  Reviews: \(output.reviewCount)")
        print("  Inline review comments: \(output.reviewCommentCount)")
    }
}
