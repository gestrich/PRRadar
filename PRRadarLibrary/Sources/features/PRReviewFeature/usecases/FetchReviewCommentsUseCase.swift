import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct FetchReviewCommentsUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(prNumber: String, minScore: Int = 5) -> [ReviewComment] {
        let prOutputDir = "\(config.absoluteOutputDir)/\(prNumber)"

        let evalsDir = "\(prOutputDir)/\(PRRadarPhase.evaluations.rawValue)"
        let tasksDir = "\(prOutputDir)/\(PRRadarPhase.tasks.rawValue)"
        let pending = ViolationService.loadViolations(
            evaluationsDir: evalsDir,
            tasksDir: tasksDir,
            minScore: minScore
        )

        let posted: [GitHubReviewComment] = {
            guard let comments: GitHubPullRequestComments = try? PhaseOutputParser.parsePhaseOutput(
                config: config,
                prNumber: prNumber,
                phase: .pullRequest,
                filename: "gh-comments.json"
            ) else { return [] }
            return comments.reviewComments
        }()

        return ViolationService.reconcile(pending: pending, posted: posted)
    }
}
