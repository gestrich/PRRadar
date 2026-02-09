import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct FetchPRListUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(
        limit: String? = nil,
        state: PRState? = .open,
        since: Date? = nil,
        repoSlug: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<[PRMetadata]>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .pullRequest))

            Task {
                do {
                    let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, tokenOverride: config.githubToken)

                    continuation.yield(.log(text: "Fetching PRs from GitHub...\n"))

                    let limitNum = Int(limit ?? "30") ?? 30

                    let prs = try await gitHub.listPullRequests(
                        limit: limitNum,
                        state: state,
                        since: since
                    )

                    // Fetch repository info once (needed by PRDiscoveryService when filtering by repoSlug)
                    let repo = try await gitHub.getRepository()

                    // Write PR data to output dir so PRDiscoveryService can find them
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                    for pr in prs {
                        let prDir = DataPathsService.phaseDirectory(
                            outputDir: config.absoluteOutputDir,
                            prNumber: String(pr.number),
                            phase: .pullRequest
                        )
                        try DataPathsService.ensureDirectoryExists(at: prDir)
                        let prData = try encoder.encode(pr)
                        try prData.write(to: URL(fileURLWithPath: "\(prDir)/gh-pr.json"))
                        
                        let repoData = try encoder.encode(repo)
                        try repoData.write(to: URL(fileURLWithPath: "\(prDir)/gh-repo.json"))
                    }

                    let discoveredPRs = PRDiscoveryService.discoverPRs(
                        outputDir: config.absoluteOutputDir,
                        repoSlug: repoSlug
                    )
                    continuation.yield(.completed(output: discoveredPRs))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }
}
