import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct FetchReviewCommentsUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    /// Loads review comments, optionally fetching fresh data from GitHub first.
    ///
    /// When `cachedOnly` is `false`, fetches comments from GitHub via
    /// `PRAcquisitionService.refreshComments()` and writes them to disk before loading.
    public func execute(
        prNumber: Int,
        minScore: Int = 5,
        commitHash: String? = nil,
        cachedOnly: Bool
    ) async throws -> [ReviewComment] {
        if !cachedOnly {
            let (gitHub, gitOps) = try await GitHubServiceFactory.create(
                repoPath: config.repoPath, githubAccount: config.githubAccount
            )
            let acquisition = PRAcquisitionService(gitHub: gitHub, gitOps: gitOps)
            _ = try await acquisition.refreshComments(
                prNumber: prNumber,
                outputDir: config.resolvedOutputDir,
                authorCache: AuthorCacheService()
            )
        }

        return execute(prNumber: prNumber, minScore: minScore, commitHash: commitHash)
    }

    /// Loads review comments from disk cache.
    public func execute(prNumber: Int, minScore: Int = 5, commitHash: String? = nil) -> [ReviewComment] {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

        let evalsDir = DataPathsService.phaseDirectory(
            outputDir: config.resolvedOutputDir, prNumber: prNumber, phase: .analyze, commitHash: resolvedCommit
        )
        let tasksDir = DataPathsService.phaseSubdirectory(
            outputDir: config.resolvedOutputDir, prNumber: prNumber, phase: .prepare,
            subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
        )
        let pending = ViolationService.loadViolations(
            evaluationsDir: evalsDir,
            tasksDir: tasksDir,
            minScore: minScore
        )

        let posted: [GitHubReviewComment] = {
            guard let comments: GitHubPullRequestComments = try? PhaseOutputParser.parsePhaseOutput(
                config: config,
                prNumber: prNumber,
                phase: .metadata,
                filename: DataPathsService.ghCommentsFilename
            ) else { return [] }
            return comments.reviewComments
        }()

        return ViolationService.reconcile(pending: pending, posted: posted)
    }
}
