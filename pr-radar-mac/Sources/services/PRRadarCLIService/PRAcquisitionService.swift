import Foundation
import PRRadarConfigService
import PRRadarModels

public struct PRAcquisitionService: Sendable {
    private let gitHub: GitHubService
    private let gitOps: GitOperationsService

    public init(gitHub: GitHubService, gitOps: GitOperationsService) {
        self.gitHub = gitHub
        self.gitOps = gitOps
    }

    public struct AcquisitionResult: Sendable {
        public let pullRequest: GitHubPullRequest
        public let diff: GitDiff
        public let comments: GitHubPullRequestComments
        public let repository: GitHubRepository
    }

    /// Fetch all PR data artifacts and write them to the phase-1 output directory.
    ///
    /// Fetches PR metadata, diff content, comments, and repository info from GitHub,
    /// parses the diff, and writes all artifacts to disk.
    public func acquire(
        prNumber: Int,
        repoPath: String,
        outputDir: String
    ) async throws -> AcquisitionResult {
        let prNumberStr = String(prNumber)
        let phaseDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumberStr,
            phase: .pullRequest
        )
        try DataPathsService.ensureDirectoryExists(at: phaseDir)

        let repository = try await gitHub.getRepository()

        let rawDiff = try await gitHub.getPRDiff(number: prNumber)
        try write(rawDiff, to: "\(phaseDir)/diff-raw.diff")

        let pullRequest = try await gitHub.getPullRequest(number: prNumber)
        let prJSON = try JSONEncoder.prettyPrinted.encode(pullRequest)
        try write(prJSON, to: "\(phaseDir)/gh-pr.json")

        let commitHash = pullRequest.headRefOid ?? ""
        let gitDiff = GitDiff.fromDiffContent(rawDiff, commitHash: commitHash)
        let parsedDiffJSON = try JSONEncoder.prettyPrinted.encode(gitDiff)
        try write(parsedDiffJSON, to: "\(phaseDir)/diff-parsed.json")

        let parsedMD = formatDiffAsMarkdown(gitDiff)
        try write(parsedMD, to: "\(phaseDir)/diff-parsed.md")

        // Effective diff placeholder — writes identity copies until Phase 4 ports the algorithm
        try write(parsedDiffJSON, to: "\(phaseDir)/effective-diff-parsed.json")
        try write(parsedMD, to: "\(phaseDir)/effective-diff-parsed.md")

        let emptyMoveReport = MoveReport(
            movesDetected: 0,
            totalLinesMoved: 0,
            totalLinesEffectivelyChanged: gitDiff.hunks.count,
            moves: []
        )
        let movesJSON = try JSONEncoder.prettyPrinted.encode(emptyMoveReport)
        try write(movesJSON, to: "\(phaseDir)/effective-diff-moves.json")

        let comments = try await gitHub.getPullRequestComments(number: prNumber)
        let commentsJSON = try JSONEncoder.prettyPrinted.encode(comments)
        try write(commentsJSON, to: "\(phaseDir)/gh-comments.json")

        let repoJSON = try JSONEncoder.prettyPrinted.encode(repository)
        try write(repoJSON, to: "\(phaseDir)/gh-repo.json")

        return AcquisitionResult(
            pullRequest: pullRequest,
            diff: gitDiff,
            comments: comments,
            repository: repository
        )
    }

    // MARK: - Private

    private func write(_ string: String, to path: String) throws {
        try string.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func write(_ data: Data, to path: String) throws {
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func formatDiffAsMarkdown(_ diff: GitDiff) -> String {
        var lines: [String] = []
        lines.append("# Diff (commit: \(diff.commitHash))")
        lines.append("")

        for hunk in diff.hunks {
            lines.append("## \(hunk.filePath)")
            lines.append("```diff")
            lines.append(hunk.content)
            lines.append("```")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - JSONEncoder Extension

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
