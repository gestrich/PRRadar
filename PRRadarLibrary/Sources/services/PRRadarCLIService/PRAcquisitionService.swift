import Foundation
import GitHubSDK
import GitSDK
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
    private let historyProvider: GitHistoryProvider
    private let imageDownload: ImageDownloadService

    public init(gitHub: GitHubService, gitOps: GitOperationsService, historyProvider: GitHistoryProvider, imageDownload: ImageDownloadService = ImageDownloadService()) {
        self.gitHub = gitHub
        self.gitOps = gitOps
        self.historyProvider = historyProvider
        self.imageDownload = imageDownload
    }

    public struct AcquisitionResult: Sendable {
        public let pullRequest: GitHubPullRequest
        public let diff: GitDiff
        public let comments: GitHubPullRequestComments
        public let repository: GitHubRepository
        public let commitHash: String
    }

    /// Fetch comments from GitHub, resolve author names, and write to `metadata/gh-comments.json`.
    ///
    /// Shared by `acquire()` (full sync) and `FetchReviewCommentsUseCase` (comment-only refresh).
    public func refreshComments(
        prNumber: Int,
        outputDir: String,
        authorCache: AuthorCacheService? = nil
    ) async throws -> GitHubPullRequestComments {
        var comments: GitHubPullRequestComments
        do {
            comments = try await gitHub.getPullRequestComments(number: prNumber)
        } catch {
            throw AcquisitionError.fetchCommentsFailed(underlying: error)
        }

        if let authorCache {
            let logins = collectCommentAuthorLogins(comments: comments)
            if !logins.isEmpty {
                let nameMap = try await gitHub.resolveAuthorNames(logins: logins, cache: authorCache)
                comments = comments.withAuthorNames(from: nameMap)
            }
        }

        let metadataDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumber,
            phase: .metadata
        )
        try DataPathsService.ensureDirectoryExists(at: metadataDir)

        let commentsJSON = try JSONEncoder.prettyPrinted.encode(comments)
        try write(commentsJSON, to: "\(metadataDir)/\(DataPathsService.ghCommentsFilename)")

        return comments
    }

    /// Fetch all PR data artifacts and write them to disk.
    ///
    /// Splits output into two locations:
    /// - PR metadata (`gh-pr.json`, `gh-comments.json`, `gh-repo.json`, images) → `metadata/`
    /// - Diff artifacts → `analysis/<commit>/diff/`
    public func acquire(
        prNumber: Int,
        outputDir: String,
        authorCache: AuthorCacheService? = nil
    ) async throws -> AcquisitionResult {
        // --- Fetch all data ---

        let repository: GitHubRepository
        do {
            repository = try await gitHub.getRepository()
        } catch {
            throw AcquisitionError.fetchRepositoryFailed(underlying: error)
        }

        var pullRequest: GitHubPullRequest
        do {
            pullRequest = try await gitHub.getPullRequest(number: prNumber)
        } catch {
            throw AcquisitionError.fetchMetadataFailed(underlying: error)
        }

        let rawDiff: String
        do {
            rawDiff = try await historyProvider.getRawDiff()
        } catch {
            throw AcquisitionError.fetchDiffFailed(underlying: error)
        }

        let comments = try await refreshComments(
            prNumber: prNumber,
            outputDir: outputDir,
            authorCache: authorCache
        )

        // Resolve PR author name (comment authors already resolved by refreshComments)
        if let authorCache {
            let prLogin = pullRequest.author?.login
            if let prLogin {
                let nameMap = try await gitHub.resolveAuthorNames(logins: [prLogin], cache: authorCache)
                pullRequest = pullRequest.withAuthorNames(from: nameMap)
            }
        }

        guard let fullCommitHash = pullRequest.headRefOid,
              let baseRefName = pullRequest.baseRefName else {
            throw AcquisitionError.missingHeadCommitSHA
        }
        let shortCommitHash = String(fullCommitHash.prefix(7))

        // --- Write PR metadata to metadata/ ---

        let metadataDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumber,
            phase: .metadata
        )
        try DataPathsService.ensureDirectoryExists(at: metadataDir)

        let prJSON = try JSONEncoder.prettyPrinted.encode(pullRequest)
        try write(prJSON, to: "\(metadataDir)/\(DataPathsService.ghPRFilename)")

        let repoJSON = try JSONEncoder.prettyPrinted.encode(repository)
        try write(repoJSON, to: "\(metadataDir)/\(DataPathsService.ghRepoFilename)")

        let imageURLMap = await downloadImages(
            prNumber: prNumber,
            pullRequest: pullRequest,
            comments: comments,
            phaseDir: metadataDir
        )
        if !imageURLMap.isEmpty {
            let mapJSON = try JSONEncoder.prettyPrinted.encode(imageURLMap)
            try write(mapJSON, to: "\(metadataDir)/\(DataPathsService.imageURLMapFilename)")
        }

        try PhaseResultWriter.writeSuccess(
            phase: .metadata,
            outputDir: outputDir,
            prNumber: prNumber,
            stats: PhaseStats(
                artifactsProduced: 3,
                metadata: ["commitHash": shortCommitHash]
            )
        )

        // --- Write diff artifacts to analysis/<commit>/diff/ ---

        let diffDir = DataPathsService.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumber,
            phase: .diff,
            commitHash: shortCommitHash
        )
        try DataPathsService.ensureDirectoryExists(at: diffDir)

        try write(rawDiff, to: "\(diffDir)/\(DataPathsService.diffRawFilename)")

        let gitDiff = GitDiff.fromDiffContent(rawDiff, commitHash: fullCommitHash)
        let parsedDiffJSON = try JSONEncoder.prettyPrinted.encode(gitDiff)
        try write(parsedDiffJSON, to: "\(diffDir)/\(DataPathsService.diffParsedJSONFilename)")

        let parsedMD = formatDiffAsMarkdown(gitDiff)
        try write(parsedMD, to: "\(diffDir)/\(DataPathsService.diffParsedMarkdownFilename)")

        let (effectiveDiffJSON, effectiveMD, movesJSON, classifiedHunksJSON) = try await runEffectiveDiff(
            gitDiff: gitDiff,
            baseRefName: baseRefName,
            headCommit: fullCommitHash,
            fallbackDiffJSON: parsedDiffJSON,
            fallbackMD: parsedMD
        )
        try write(effectiveDiffJSON, to: "\(diffDir)/\(DataPathsService.effectiveDiffParsedJSONFilename)")
        try write(effectiveMD, to: "\(diffDir)/\(DataPathsService.effectiveDiffParsedMarkdownFilename)")
        try write(movesJSON, to: "\(diffDir)/\(DataPathsService.effectiveDiffMovesFilename)")
        try write(classifiedHunksJSON, to: "\(diffDir)/\(DataPathsService.classifiedHunksFilename)")

        try PhaseResultWriter.writeSuccess(
            phase: .diff,
            outputDir: outputDir,
            prNumber: prNumber,
            commitHash: shortCommitHash,
            stats: PhaseStats(
                artifactsProduced: 7,
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

    private func collectCommentAuthorLogins(
        comments: GitHubPullRequestComments
    ) -> Set<String> {
        var logins = Set<String>()
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

    /// Run the effective diff pipeline, returning encoded JSON and markdown for the effective diff and move report.
    /// Falls back to the full diff on any error.
    private func runEffectiveDiff(
        gitDiff: GitDiff,
        baseRefName: String,
        headCommit: String,
        fallbackDiffJSON: Data,
        fallbackMD: String
    ) async throws -> (diffJSON: Data, diffMD: String, movesJSON: Data, classifiedHunksJSON: Data) {
        do {
            let mergeBase = try await historyProvider.getMergeBase(
                commit1: "origin/\(baseRefName)",
                commit2: headCommit
            )

            var oldFiles: [String: String] = [:]
            var newFiles: [String: String] = [:]
            for filePath in gitDiff.uniqueFiles {
                oldFiles[filePath] = try? await historyProvider.getFileContent(commit: mergeBase, filePath: filePath)
                newFiles[filePath] = try? await historyProvider.getFileContent(commit: headCommit, filePath: filePath)
            }

            let result = try await runEffectiveDiffPipeline(
                gitDiff: gitDiff,
                oldFiles: oldFiles,
                newFiles: newFiles,
                rediff: gitOps.diffNoIndex
            )

            let effectiveDiffJSON = try JSONEncoder.prettyPrinted.encode(result.effectiveDiff)
            let effectiveMD = formatDiffAsMarkdown(result.effectiveDiff)
            let moveReport = result.moveReport.toMoveReport()
            let movesJSON = try JSONEncoder.prettyPrinted.encode(moveReport)
            let classifiedHunksJSON = try JSONEncoder.prettyPrinted.encode(result.classifiedHunks)

            return (effectiveDiffJSON, effectiveMD, movesJSON, classifiedHunksJSON)
        } catch {
            let emptyMoveReport = MoveReport(
                movesDetected: 0,
                totalLinesMoved: 0,
                totalLinesEffectivelyChanged: gitDiff.hunks.count,
                moves: []
            )
            let movesJSON = try JSONEncoder.prettyPrinted.encode(emptyMoveReport)
            let emptyClassifiedHunksJSON = try JSONEncoder.prettyPrinted.encode([ClassifiedHunk]())
            return (fallbackDiffJSON, fallbackMD, movesJSON, emptyClassifiedHunksJSON)
        }
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
