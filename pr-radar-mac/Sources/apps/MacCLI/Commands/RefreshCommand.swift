import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct RefreshCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refresh",
        abstract: "Fetch recent PRs from GitHub"
    )

    @Option(name: .long, help: "Named configuration from settings")
    var config: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Option(name: .long, help: "Maximum number of PRs to fetch")
    var limit: String?

    @Option(name: .long, help: "PR state filter (open, closed, merged, all)")
    var state: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false

    func run() async throws {
        let resolved = try resolveConfig(
            configName: config,
            repoPath: repoPath,
            outputDir: outputDir
        )
        let prRadarConfig = resolved.config

        let useCase = FetchPRListUseCase(config: prRadarConfig)
        let repoSlug = PRDiscoveryService.repoSlug(fromRepoPath: prRadarConfig.repoPath)

        if !json {
            print("Fetching recent PRs from GitHub...")
        }

        for try await progress in useCase.execute(limit: limit, state: state, repoSlug: repoSlug) {
            switch progress {
            case .running:
                break
            case .log(let text):
                if !json { print(text, terminator: "") }
            case .completed(let prs):
                if json {
                    let encoded = prs.map { pr in
                        [
                            "number": pr.number,
                            "title": pr.title,
                            "author": pr.author.login,
                            "state": pr.state,
                            "branch": pr.headRefName,
                        ] as [String: Any]
                    }
                    let data = try JSONSerialization.data(withJSONObject: encoded, options: [.prettyPrinted, .sortedKeys])
                    print(String(data: data, encoding: .utf8)!)
                } else {
                    print("\nFetched \(prs.count) PRs:")
                    for pr in prs {
                        print("  #\(pr.number) \(pr.title) (\(pr.author.login))")
                    }
                }
            case .failed(let error, let logs):
                if !logs.isEmpty { printError(logs) }
                throw CLIError.phaseFailed("Refresh failed: \(error)")
            }
        }
    }
}
