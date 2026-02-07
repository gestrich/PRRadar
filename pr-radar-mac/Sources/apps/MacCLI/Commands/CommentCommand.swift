import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct CommentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "comment",
        abstract: "Post review comments to GitHub PR (Phase 5)"
    )

    @Argument(help: "Pull request number")
    var prNumber: String

    @Option(name: .long, help: "GitHub repo (owner/name)")
    var repo: String?

    @Option(name: .long, help: "Minimum violation score to post")
    var minScore: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Flag(name: .long, help: "Preview comments without posting")
    var dryRun: Bool = false

    func run() async throws {
        let config = resolveConfig(repoPath: repoPath, outputDir: outputDir)
        let environment = resolveEnvironment(config: config)
        let useCase = PostCommentsUseCase(config: config, environment: environment)

        if dryRun {
            print("Dry run: previewing comments for PR #\(prNumber)...")
        } else {
            print("Posting comments for PR #\(prNumber)...")
        }

        var result: CommentPhaseOutput?

        for try await progress in useCase.execute(
            prNumber: prNumber,
            repo: repo,
            minScore: minScore,
            dryRun: dryRun
        ) {
            switch progress {
            case .running:
                break
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

        if !output.cliOutput.isEmpty {
            print(output.cliOutput)
        }

        if output.posted {
            print("Comments posted successfully.")
        } else {
            print("Dry run complete. No comments posted.")
        }
    }
}
