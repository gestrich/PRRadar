import PRRadarCLIService
import PRRadarModels

public struct PostSingleCommentUseCase: Sendable {

    public init() {}

    public func execute(
        repoSlug: String,
        prNumber: String,
        filePath: String,
        lineNumber: Int?,
        commitSHA: String,
        commentBody: String,
        repoPath: String
    ) async throws -> Bool {
        let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: repoPath)
        let commentService = CommentService(githubService: gitHub)

        guard let prNum = Int(prNumber) else { return false }

        let violation = CommentableViolation(
            taskId: "",
            ruleName: "",
            filePath: filePath,
            lineNumber: lineNumber,
            score: 0,
            comment: commentBody
        )

        do {
            try await commentService.postReviewComment(
                prNumber: prNum,
                violation: violation,
                commitSHA: commitSHA
            )
            return true
        } catch {
            return false
        }
    }
}
