import Foundation
import PRRadarConfigService
import PRRadarModels

public struct PRAcquisitionService: Sendable {

    public enum AcquisitionError: LocalizedError {
        case fetchRepositoryFailed(underlying: Error)
        case fetchDiffFailed(underlying: Error)
        case fetchMetadataFailed(underlying: Error)
        case fetchCommentsFailed(underlying: Error)
        case missingHeadCommitSHA

        public var errorDescription: String? {
            switch self {
            case .fetchRepositoryFailed(let error):
                "Failed to fetch repository info: \(error.localizedDescription)"
            case .fetchDiffFailed(let error):
                "Failed to fetch PR diff: \(error.localizedDescription)"
            case .fetchMetadataFailed(let error):
                "Failed to fetch PR metadata: \(error.localizedDescription)"
            case .fetchCommentsFailed(let error):
                "Failed to fetch PR comments: \(error.localizedDescription)"
            case .missingHeadCommitSHA:
                "PR is missing headRefOid (head commit SHA)"
            }
        }
    }

    private let gitHub: GitHubService
    private let gitOps: GitOperationsService
    private let imageDownload: ImageDownloadService

    public init(gitHub: GitHubService, gitOps: GitOperationsService, imageDownload: ImageDownloadService = ImageDownloadService()) {
        self.gitHub = gitHub
        self.gitOps = gitOps
        self.imageDownload = imageDownload
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
        outputDir: String,
        authorCache: AuthorCacheService? = nil
    ) async throws -> AcquisitionResult {
        let prNumberStr = String(prNumber)
        let phaseDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumberStr,
            phase: .sync
        )
        try DataPathsService.ensureDirectoryExists(at: phaseDir)

        let repository: GitHubRepository
        do {
            repository = try await gitHub.getRepository()
        } catch {
            throw AcquisitionError.fetchRepositoryFailed(underlying: error)
        }

        let rawDiff: String
        do {
            rawDiff = try await gitHub.getPRDiff(number: prNumber)
            try write(rawDiff, to: "\(phaseDir)/diff-raw.diff")
        } catch {
            throw AcquisitionError.fetchDiffFailed(underlying: error)
        }

        var pullRequest: GitHubPullRequest
        do {
            pullRequest = try await gitHub.getPullRequest(number: prNumber)
        } catch {
            throw AcquisitionError.fetchMetadataFailed(underlying: error)
        }

        var comments: GitHubPullRequestComments
        do {
            comments = try await gitHub.getPullRequestComments(number: prNumber)
        } catch {
            throw AcquisitionError.fetchCommentsFailed(underlying: error)
        }

        // Resolve author display names via cache
        if let authorCache {
            let logins = collectAuthorLogins(pullRequest: pullRequest, comments: comments)
            if !logins.isEmpty {
                let nameMap = try await gitHub.resolveAuthorNames(logins: logins, cache: authorCache)
                pullRequest = pullRequest.withAuthorNames(from: nameMap)
                comments = comments.withAuthorNames(from: nameMap)
            }
        }

        let prJSON = try JSONEncoder.prettyPrinted.encode(pullRequest)
        try write(prJSON, to: "\(phaseDir)/gh-pr.json")

        guard let commitHash = pullRequest.headRefOid else {
            throw AcquisitionError.missingHeadCommitSHA
        }
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

        let commentsJSON = try JSONEncoder.prettyPrinted.encode(comments)
        try write(commentsJSON, to: "\(phaseDir)/gh-comments.json")

        let repoJSON = try JSONEncoder.prettyPrinted.encode(repository)
        try write(repoJSON, to: "\(phaseDir)/gh-repo.json")

        // Download images from PR body and comments
        let imageURLMap = await downloadImages(
            prNumber: prNumber,
            pullRequest: pullRequest,
            comments: comments,
            phaseDir: phaseDir
        )
        if !imageURLMap.isEmpty {
            let mapJSON = try JSONEncoder.prettyPrinted.encode(imageURLMap)
            try write(mapJSON, to: "\(phaseDir)/image-url-map.json")
        }

        // Write phase_result.json to mark successful completion
        try PhaseResultWriter.writeSuccess(
            phase: .sync,
            outputDir: outputDir,
            prNumber: prNumberStr,
            stats: PhaseStats(
                artifactsProduced: 9,  // Number of required files
                metadata: ["files": String(gitDiff.uniqueFiles.count), "hunks": String(gitDiff.hunks.count)]
            )
        )

        return AcquisitionResult(
            pullRequest: pullRequest,
            diff: gitDiff,
            comments: comments,
            repository: repository
        )
    }

    // MARK: - Private

    private func collectAuthorLogins(
        pullRequest: GitHubPullRequest,
        comments: GitHubPullRequestComments
    ) -> Set<String> {
        var logins = Set<String>()
        if let login = pullRequest.author?.login {
            logins.insert(login)
        }
        for c in comments.comments {
            if let login = c.author?.login {
                logins.insert(login)
            }
        }
        for r in comments.reviews {
            if let login = r.author?.login {
                logins.insert(login)
            }
        }
        for rc in comments.reviewComments {
            if let login = rc.author?.login {
                logins.insert(login)
            }
        }
        return logins
    }

    private func downloadImages(
        prNumber: Int,
        pullRequest: GitHubPullRequest,
        comments: GitHubPullRequestComments,
        phaseDir: String
    ) async -> [String: String] {
        do {
            let bodyHTML = try await gitHub.fetchBodyHTML(number: prNumber)
            let imagesDir = "\(phaseDir)/images"

            var allResolved: [String: URL] = [:]

            // Resolve images from PR body
            if let body = pullRequest.body {
                let resolved = imageDownload.resolveImageURLs(body: body, bodyHTML: bodyHTML)
                allResolved.merge(resolved) { _, new in new }
            }

            // Resolve images from issue comments
            for comment in comments.comments {
                let resolved = imageDownload.resolveImageURLs(body: comment.body, bodyHTML: bodyHTML)
                allResolved.merge(resolved) { _, new in new }
            }

            guard !allResolved.isEmpty else { return [:] }

            return try await imageDownload.downloadImages(urls: allResolved, to: imagesDir)
        } catch {
            // Image download failures are non-fatal
            return [:]
        }
    }

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
