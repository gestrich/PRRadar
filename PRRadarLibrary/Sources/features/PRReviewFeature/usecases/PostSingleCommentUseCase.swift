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
        prNumber: Int
    ) async throws -> Bool {
        let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)
        let commentService = CommentService(githubService: gitHub)

        do {
            try await commentService.postReviewComment(
                prNumber: prNumber,
                comment: comment,
                commitSHA: commitSHA
            )
            return true
        } catch {
            return false
        }
    }
}
