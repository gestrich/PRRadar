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
        public let commitHash: String
    }

    /// Fetch all PR data artifacts and write them to disk.
    ///
    /// Splits output into two locations:
    /// - PR metadata (`gh-pr.json`, `gh-comments.json`, `gh-repo.json`, images) → `metadata/`
    /// - Diff artifacts → `analysis/<commit>/diff/`
    public func acquire(
        prNumber: Int,
        repoPath: String,
        outputDir: String,
        authorCache: AuthorCacheService? = nil
    ) async throws -> AcquisitionResult {
        let prNumberStr = String(prNumber)

        // --- Fetch all data from GitHub ---

        let repository: GitHubRepository
        do {
            repository = try await gitHub.getRepository()
        } catch {
            throw AcquisitionError.fetchRepositoryFailed(underlying: error)
        }

        let rawDiff: String
        do {
            rawDiff = try await gitHub.getPRDiff(number: prNumber)
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

        guard let fullCommitHash = pullRequest.headRefOid else {
            throw AcquisitionError.missingHeadCommitSHA
        }
        let shortCommitHash = String(fullCommitHash.prefix(7))

        // --- Write PR metadata to metadata/ ---

        let metadataDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumberStr,
            phase: .metadata
        )
        try DataPathsService.ensureDirectoryExists(at: metadataDir)

        let prJSON = try JSONEncoder.prettyPrinted.encode(pullRequest)
        try write(prJSON, to: "\(metadataDir)/gh-pr.json")

        let commentsJSON = try JSONEncoder.prettyPrinted.encode(comments)
        try write(commentsJSON, to: "\(metadataDir)/gh-comments.json")

        let repoJSON = try JSONEncoder.prettyPrinted.encode(repository)
        try write(repoJSON, to: "\(metadataDir)/gh-repo.json")

        let imageURLMap = await downloadImages(
            prNumber: prNumber,
            pullRequest: pullRequest,
            comments: comments,
            phaseDir: metadataDir
        )
        if !imageURLMap.isEmpty {
            let mapJSON = try JSONEncoder.prettyPrinted.encode(imageURLMap)
            try write(mapJSON, to: "\(metadataDir)/image-url-map.json")
        }

        try PhaseResultWriter.writeSuccess(
            phase: .metadata,
            outputDir: outputDir,
            prNumber: prNumberStr,
            stats: PhaseStats(
                artifactsProduced: 3,
                metadata: ["commitHash": shortCommitHash]
            )
        )

        // --- Write diff artifacts to analysis/<commit>/diff/ ---

        let diffDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumberStr,
            phase: .diff,
            commitHash: shortCommitHash
        )
        try DataPathsService.ensureDirectoryExists(at: diffDir)

        try write(rawDiff, to: "\(diffDir)/diff-raw.diff")

        let gitDiff = GitDiff.fromDiffContent(rawDiff, commitHash: fullCommitHash)
        let parsedDiffJSON = try JSONEncoder.prettyPrinted.encode(gitDiff)
        try write(parsedDiffJSON, to: "\(diffDir)/diff-parsed.json")

        let parsedMD = formatDiffAsMarkdown(gitDiff)
        try write(parsedMD, to: "\(diffDir)/diff-parsed.md")

        try write(parsedDiffJSON, to: "\(diffDir)/effective-diff-parsed.json")
        try write(parsedMD, to: "\(diffDir)/effective-diff-parsed.md")

        let emptyMoveReport = MoveReport(
            movesDetected: 0,
            totalLinesMoved: 0,
            totalLinesEffectivelyChanged: gitDiff.hunks.count,
            moves: []
        )
        let movesJSON = try JSONEncoder.prettyPrinted.encode(emptyMoveReport)
        try write(movesJSON, to: "\(diffDir)/effective-diff-moves.json")

        try PhaseResultWriter.writeSuccess(
            phase: .diff,
            outputDir: outputDir,
            prNumber: prNumberStr,
            commitHash: shortCommitHash,
            stats: PhaseStats(
                artifactsProduced: 6,
                metadata: ["files": String(gitDiff.uniqueFiles.count), "hunks": String(gitDiff.hunks.count)]
            )
        )

        return AcquisitionResult(
            pullRequest: pullRequest,
            diff: gitDiff,
            comments: comments,
            repository: repository,
            commitHash: shortCommitHash
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
