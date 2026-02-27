import PRRadarCLIService
import PRRadarConfigService

public struct PostManualCommentUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(
        prNumber: Int,
        filePath: String,
        lineNumber: Int,
        body: String,
        commitSHA: String
    ) async throws -> Bool {
        let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)

        do {
            try await gitHub.postReviewComment(
                number: prNumber,
                commitId: commitSHA,
                path: filePath,
                line: lineNumber,
                body: body
            )
            return true
        } catch {
            return false
        }
    }
}
