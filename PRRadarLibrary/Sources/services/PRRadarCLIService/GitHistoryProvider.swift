public protocol GitHistoryProvider: Sendable {
    /// Get the raw unified diff for the PR.
    func getRawDiff() async throws -> String

    /// Get the content of a file at a specific commit.
    func getFileContent(commit: String, filePath: String) async throws -> String

    /// Find the merge base between two commits.
    func getMergeBase(commit1: String, commit2: String) async throws -> String

    /// Get the blob hash of a file at a specific commit (for caching).
    func getBlobHash(commit: String, filePath: String) async throws -> String

    /// Ensure the given ref is available for subsequent operations.
    /// For git CLI, this fetches the ref. For GitHub API, this is a no-op.
    func ensureRefAvailable(remote: String, ref: String) async throws
}
