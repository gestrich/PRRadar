import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct FetchReviewCommentsUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(prNumber: String, minScore: Int = 5, commitHash: String? = nil) -> [ReviewComment] {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

        let evalsDir = DataPathsService.phaseDirectory(
            outputDir: config.absoluteOutputDir, prNumber: prNumber, phase: .analyze, commitHash: resolvedCommit
        )
        let tasksDir = DataPathsService.phaseSubdirectory(
            outputDir: config.absoluteOutputDir, prNumber: prNumber, phase: .prepare,
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
