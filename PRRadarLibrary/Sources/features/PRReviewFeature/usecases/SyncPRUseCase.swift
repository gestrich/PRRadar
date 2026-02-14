import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct SyncSnapshot: Sendable {
    public let files: [String]
    public let fullDiff: GitDiff?
    public let effectiveDiff: GitDiff?
    public let moveReport: MoveReport?
    public let commentCount: Int
    public let reviewCount: Int
    public let reviewCommentCount: Int
    public let commitHash: String?

    public init(
        files: [String],
        fullDiff: GitDiff?,
        effectiveDiff: GitDiff?,
        moveReport: MoveReport?,
        commentCount: Int = 0,
        reviewCount: Int = 0,
        reviewCommentCount: Int = 0,
        commitHash: String? = nil
    ) {
        self.files = files
        self.fullDiff = fullDiff
        self.effectiveDiff = effectiveDiff
        self.moveReport = moveReport
        self.commentCount = commentCount
        self.reviewCount = reviewCount
        self.reviewCommentCount = reviewCommentCount
        self.commitHash = commitHash
    }
}

public struct SyncPRUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public static func parseOutput(config: PRRadarConfig, prNumber: String, commitHash: String? = nil) -> SyncSnapshot {
        let resolvedCommit = commitHash ?? resolveCommitHash(config: config, prNumber: prNumber)

        // Diff files live under analysis/<commit>/diff/
        let files = OutputFileReader.files(
            in: config,
            prNumber: prNumber,
            phase: .diff,
            commitHash: resolvedCommit
        )

        let fullDiff: GitDiff? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .diff, filename: DataPathsService.diffParsedJSONFilename, commitHash: resolvedCommit
        )

        let effectiveDiff: GitDiff? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .diff, filename: DataPathsService.effectiveDiffParsedJSONFilename, commitHash: resolvedCommit
        )

        let moveReport: MoveReport? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .diff, filename: DataPathsService.effectiveDiffMovesFilename, commitHash: resolvedCommit
        )

        // Comments live under metadata/
        let comments: GitHubPullRequestComments? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .metadata, filename: DataPathsService.ghCommentsFilename
        )

        return SyncSnapshot(
            files: files,
            fullDiff: fullDiff,
            effectiveDiff: effectiveDiff,
            moveReport: moveReport,
            commentCount: comments?.comments.count ?? 0,
            reviewCount: comments?.reviews.count ?? 0,
            reviewCommentCount: comments?.reviewComments.count ?? 0,
            commitHash: resolvedCommit
        )
    }

    /// Resolve the commit hash from metadata/gh-pr.json, or scan analysis/ for the latest commit directory.
    public static func resolveCommitHash(config: PRRadarConfig, prNumber: String) -> String? {
        // Try reading headRefOid from metadata/gh-pr.json
        let metadataDir = DataPathsService.phaseDirectory(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber,
            phase: .metadata
        )
        let ghPRPath = "\(metadataDir)/gh-pr.json"
        if let data = FileManager.default.contents(atPath: ghPRPath),
           let pr = try? JSONDecoder().decode(GitHubPullRequest.self, from: data),
           let fullHash = pr.headRefOid {
            return String(fullHash.prefix(7))
        }
        // Fallback: pick the most recent commit directory under analysis/
        let analysisRoot = "\(config.absoluteOutputDir)/\(prNumber)/\(DataPathsService.analysisDirectoryName)"
        if let dirs = try? FileManager.default.contentsOfDirectory(atPath: analysisRoot) {
            return dirs.sorted().last
        }
        return nil
    }

    public func execute(prNumber: String) -> AsyncThrowingStream<PhaseProgress<SyncSnapshot>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .diff))

            Task {
                do {
                    try Task.checkCancellation()

                    let (gitHub, gitOps) = try await GitHubServiceFactory.create(repoPath: config.repoPath)
                    let acquisition = PRAcquisitionService(gitHub: gitHub, gitOps: gitOps)
                    let authorCache = AuthorCacheService()

                    guard let prNum = Int(prNumber) else {
                        continuation.yield(.failed(error: "Invalid PR number: \(prNumber)", logs: ""))
                        continuation.finish()
                        return
                    }

                    try Task.checkCancellation()

                    continuation.yield(.log(text: "Fetching PR #\(prNumber) from GitHub...\n"))

                    let result = try await acquisition.acquire(
                        prNumber: prNum,
                        repoPath: config.repoPath,
                        outputDir: config.absoluteOutputDir,
                        authorCache: authorCache
                    )

                    try Task.checkCancellation()

                    let comments = result.comments
                    continuation.yield(.log(text: "Diff acquired: \(result.diff.hunks.count) hunks across \(result.diff.uniqueFiles.count) files\n"))
                    continuation.yield(.log(text: "Comments: \(comments.comments.count) issue, \(comments.reviews.count) reviews, \(comments.reviewComments.count) inline\n"))

                    for rc in comments.reviewComments {
                        let author = rc.author?.login ?? "unknown"
                        let file = rc.path.split(separator: "/").last.map(String.init) ?? rc.path
                        continuation.yield(.log(text: "  [\(author)] \(file):\(rc.line ?? 0) — \(rc.body.prefix(80))\n"))
                    }

                    let snapshot = Self.parseOutput(config: config, prNumber: prNumber, commitHash: result.commitHash)
                    continuation.yield(.completed(output: snapshot))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }
}
