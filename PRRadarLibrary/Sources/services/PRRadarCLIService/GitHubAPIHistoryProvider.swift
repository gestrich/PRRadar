import GitHubSDK

public struct GitHubAPIHistoryProvider: GitHistoryProvider {
    private let gitHub: GitHubService
    private let prNumber: Int

    public init(gitHub: GitHubService, prNumber: Int) {
        self.gitHub = gitHub
        self.prNumber = prNumber
    }

    public func getRawDiff() async throws -> String {
        try await gitHub.getPRDiff(number: prNumber)
    }

    public func getFileContent(commit: String, filePath: String) async throws -> String {
        try await gitHub.getFileContent(path: filePath, ref: commit)
    }

    public func getMergeBase(commit1: String, commit2: String) async throws -> String {
        let result = try await gitHub.compareCommits(base: commit1, head: commit2)
        return result.mergeBaseCommitSHA
    }

    public func getBlobHash(commit: String, filePath: String) async throws -> String {
        try await gitHub.getFileSHA(path: filePath, ref: commit)
    }
}
