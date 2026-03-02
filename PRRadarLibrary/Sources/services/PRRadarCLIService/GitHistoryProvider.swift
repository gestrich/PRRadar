public protocol GitHistoryProvider: Sendable {
    /// Get the raw unified diff for the PR.
    func getRawDiff() async throws -> String

    /// Get the content of a file at a specific commit.
    func getFileContent(commit: String, filePath: String) async throws -> String

    /// Find the merge base between two commits.
    func getMergeBase(commit1: String, commit2: String) async throws -> String

    /// Get the blob hash of a file at a specific commit (for caching).
    func getBlobHash(commit: String, filePath: String) async throws -> String
}
