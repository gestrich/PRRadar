import PRRadarCLIService
import PRRadarModels

public struct PostSingleCommentUseCase: Sendable {

    public init() {}

    public func execute(
        comment: PRComment,
        commitSHA: String,
        prNumber: String,
        repoPath: String,
        githubToken: String? = nil
    ) async throws -> Bool {
        let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: repoPath, tokenOverride: githubToken)
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
