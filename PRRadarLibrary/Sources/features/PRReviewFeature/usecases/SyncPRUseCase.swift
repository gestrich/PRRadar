import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct SyncSnapshot: Sendable {
    public let files: [String]
    public let fullDiff: GitDiff?
    public let effectiveDiff: GitDiff?
    public let moveReport: MoveReport?
    public let classifiedHunks: [ClassifiedHunk]?
    public let commentCount: Int
    public let reviewCount: Int
    public let reviewCommentCount: Int
    public let commitHash: String?

    public init(
        files: [String],
        fullDiff: GitDiff?,
        effectiveDiff: GitDiff?,
        moveReport: MoveReport?,
        classifiedHunks: [ClassifiedHunk]? = nil,
        commentCount: Int = 0,
        reviewCount: Int = 0,
        reviewCommentCount: Int = 0,
        commitHash: String? = nil
    ) {
        self.files = files
        self.fullDiff = fullDiff
        self.effectiveDiff = effectiveDiff
        self.moveReport = moveReport
        self.classifiedHunks = classifiedHunks
        self.commentCount = commentCount
        self.reviewCount = reviewCount
        self.reviewCommentCount = reviewCommentCount
        self.commitHash = commitHash
    }
}

public struct SyncPRUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public static func parseOutput(config: RepositoryConfiguration, prNumber: Int, commitHash: String? = nil) -> SyncSnapshot {
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

        let classifiedHunks: [ClassifiedHunk]? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .diff, filename: DataPathsService.classifiedHunksFilename, commitHash: resolvedCommit
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
            classifiedHunks: classifiedHunks,
            commentCount: comments?.comments.count ?? 0,
            reviewCount: comments?.reviews.count ?? 0,
            reviewCommentCount: comments?.reviewComments.count ?? 0,
            commitHash: resolvedCommit
        )
    }

    /// Resolve the commit hash from metadata/gh-pr.json, or scan analysis/ for the latest commit directory.
    public static func resolveCommitHash(config: RepositoryConfiguration, prNumber: Int) -> String? {
        // Try reading headRefOid from metadata/gh-pr.json
        let metadataDir = DataPathsService.phaseDirectory(
            outputDir: config.resolvedOutputDir,
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
        let analysisRoot = "\(config.resolvedOutputDir)/\(prNumber)/\(DataPathsService.analysisDirectoryName)"
        if let dirs = try? FileManager.default.contentsOfDirectory(atPath: analysisRoot) {
            return dirs.sorted().last
        }
        return nil
    }

    public func execute(prNumber: Int, force: Bool = false) -> AsyncThrowingStream<PhaseProgress<SyncSnapshot>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .diff))

            Task {
                do {
                    try Task.checkCancellation()

                    let (gitHub, gitOps) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)

                    try Task.checkCancellation()

                    if !force {
                        let cachedPR: GitHubPullRequest? = try? PhaseOutputParser.parsePhaseOutput(
                            config: config, prNumber: prNumber, phase: .metadata, filename: DataPathsService.ghPRFilename
                        )
                        if let cachedUpdatedAt = cachedPR?.updatedAt {
                            let currentUpdatedAt = try await gitHub.getPRUpdatedAt(number: prNumber)
                            if cachedUpdatedAt == currentUpdatedAt {
                                let snapshot = Self.parseOutput(config: config, prNumber: prNumber)
                                continuation.yield(.completed(output: snapshot))
                                continuation.finish()
                                return
                            }
                        }
                    }

                    let prMetadata = try await gitHub.getPullRequest(number: prNumber)
                    guard let baseBranch = prMetadata.baseRefName,
                          let headBranch = prMetadata.headRefName else {
                        throw PRAcquisitionService.AcquisitionError.missingHeadCommitSHA
                    }
                    let historyProvider = GitHubServiceFactory.createHistoryProvider(
                        diffSource: config.diffSource,
                        gitHub: gitHub,
                        gitOps: gitOps,
                        repoPath: config.repoPath,
                        prNumber: prNumber,
                        baseBranch: baseBranch,
                        headBranch: headBranch
                    )
                    let acquisition = PRAcquisitionService(gitHub: gitHub, gitOps: gitOps, historyProvider: historyProvider)
                    let authorCache = AuthorCacheService()

                    continuation.yield(.log(text: "Fetching PR #\(prNumber) from GitHub...\n"))

                    let result = try await acquisition.acquire(
                        prNumber: prNumber,
                        outputDir: config.resolvedOutputDir,
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
