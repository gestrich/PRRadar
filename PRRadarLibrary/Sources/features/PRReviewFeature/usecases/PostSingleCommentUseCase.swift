import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct PostSingleCommentUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(
        comment: PRComment,
        commitSHA: String,
        prNumber: String
    ) async throws -> Bool {
        let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, credentialAccount: config.credentialAccount)
        let commentService = CommentService(githubService: gitHub)

        guard let prNum = Int(prNumber) else { return false }

        do {
            try await commentService.postReviewComment(
                prNumber: prNum,
                comment: comment,
                commitSHA: commitSHA
            )
            return true
        } catch {
            return false
        }
    }
}
