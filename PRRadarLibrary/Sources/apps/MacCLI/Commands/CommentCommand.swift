import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct CommentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "comment",
        abstract: "Post review comments to GitHub PR (Phase 5)"
    )

    @OptionGroup var options: CLIOptions

    @Option(name: .long, help: "Minimum violation score to post")
    var minScore: String?

    @Flag(name: .long, help: "Preview comments without posting")
    var dryRun: Bool = false

    func run() async throws {
        let resolved = try resolveConfigFromOptions(options)
        let config = resolved.config
        let useCase = PostCommentsUseCase(config: config)

        if dryRun {
            print("Dry run: previewing comments for PR #\(options.prNumber)...")
        } else {
            print("Posting comments for PR #\(options.prNumber)...")
        }

        var result: CommentPhaseOutput?

        for try await progress in useCase.execute(
            prNumber: options.prNumber,
            minScore: minScore,
            dryRun: dryRun
        ) {
            switch progress {
            case .running:
                break
            case .progress:
                break
            case .log(let text):
                print(text, terminator: "")
            case .aiOutput: break
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printError(logs)
                }
                throw CLIError.phaseFailed("Comment failed: \(error)")
            }
        }

        guard let output = result else {
            throw CLIError.phaseFailed("Comment phase produced no output")
        }

        if output.posted {
            print("\(output.successful) comments posted, \(output.failed) failed.")
        } else {
            print("Dry run complete. \(output.violations.count) comments would be posted.")
        }
    }
}
