import GitSDK

public struct LocalGitHistoryProvider: GitHistoryProvider {
    private let gitOps: GitOperationsService
    private let repoPath: String
    private let baseBranch: String
    private let headBranch: String
    private let remote: String

    public init(gitOps: GitOperationsService, repoPath: String, baseBranch: String = "", headBranch: String = "", remote: String = "origin") {
        self.gitOps = gitOps
        self.repoPath = repoPath
        self.baseBranch = baseBranch
        self.headBranch = headBranch
        self.remote = remote
    }

    public func getRawDiff() async throws -> String {
        try await gitOps.getBranchDiff(base: baseBranch, head: headBranch, remote: remote, repoPath: repoPath)
    }

    public func getFileContent(commit: String, filePath: String) async throws -> String {
        try await gitOps.getFileContent(commit: commit, filePath: filePath, repoPath: repoPath)
    }

    public func getMergeBase(commit1: String, commit2: String) async throws -> String {
        try await gitOps.getMergeBase(commit1: commit1, commit2: commit2, repoPath: repoPath)
    }

    public func getBlobHash(commit: String, filePath: String) async throws -> String {
        try await gitOps.getBlobHash(commit: commit, filePath: filePath, repoPath: repoPath)
    }
}
