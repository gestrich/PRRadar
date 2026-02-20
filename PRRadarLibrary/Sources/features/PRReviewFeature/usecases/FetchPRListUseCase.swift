import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct FetchPRListUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(
        limit: String? = nil,
        state: PRState? = .open,
        since: Date? = nil,
        repoSlug: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<[PRMetadata]>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .diff))

            Task {
                do {
                    let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)

                    continuation.yield(.log(text: "Fetching PRs from GitHub...\n"))

                    let limitNum = Int(limit ?? "30") ?? 30

                    let prs = try await gitHub.listPullRequests(
                        limit: limitNum,
                        state: state,
                        since: since
                    )

                    // Fetch repository info once (needed by PRDiscoveryService when filtering by repoSlug)
                    let repo = try await gitHub.getRepository()

                    // Resolve author display names via cache
                    let authorCache = AuthorCacheService()
                    let authorLogins = Set(prs.compactMap { $0.author?.login })
                    let nameMap = authorLogins.isEmpty ? [:] : try await gitHub.resolveAuthorNames(logins: authorLogins, cache: authorCache)

                    // Write PR data to output dir so PRDiscoveryService can find them
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                    for pr in prs.map({ $0.withAuthorNames(from: nameMap) }) {
                        let metadataDir = DataPathsService.metadataDirectory(
                            outputDir: config.resolvedOutputDir,
                            prNumber: pr.number
                        )
                        try DataPathsService.ensureDirectoryExists(at: metadataDir)
                        let prData = try encoder.encode(pr)
                        try prData.write(to: URL(fileURLWithPath: "\(metadataDir)/\(DataPathsService.ghPRFilename)"))

                        let repoData = try encoder.encode(repo)
                        try repoData.write(to: URL(fileURLWithPath: "\(metadataDir)/\(DataPathsService.ghRepoFilename)"))
                    }

                    let discoveredPRs = PRDiscoveryService.discoverPRs(
                        outputDir: config.resolvedOutputDir,
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
