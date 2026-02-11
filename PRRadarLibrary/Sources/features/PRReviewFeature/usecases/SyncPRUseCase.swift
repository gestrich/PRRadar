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

    public init(
        files: [String],
        fullDiff: GitDiff?,
        effectiveDiff: GitDiff?,
        moveReport: MoveReport?,
        commentCount: Int = 0,
        reviewCount: Int = 0,
        reviewCommentCount: Int = 0
    ) {
        self.files = files
        self.fullDiff = fullDiff
        self.effectiveDiff = effectiveDiff
        self.moveReport = moveReport
        self.commentCount = commentCount
        self.reviewCount = reviewCount
        self.reviewCommentCount = reviewCommentCount
    }
}

public struct SyncPRUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public static func parseOutput(config: PRRadarConfig, prNumber: String) -> SyncSnapshot {
        let files = OutputFileReader.files(
            in: config,
            prNumber: prNumber,
            phase: .sync
        )

        let fullDiff: GitDiff? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .sync, filename: "diff-parsed.json"
        )

        let effectiveDiff: GitDiff? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .sync, filename: "effective-diff-parsed.json"
        )

        let moveReport: MoveReport? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .sync, filename: "effective-diff-moves.json"
        )

        let comments: GitHubPullRequestComments? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .sync, filename: "gh-comments.json"
        )

        return SyncSnapshot(
            files: files,
            fullDiff: fullDiff,
            effectiveDiff: effectiveDiff,
            moveReport: moveReport,
            commentCount: comments?.comments.count ?? 0,
            reviewCount: comments?.reviews.count ?? 0,
            reviewCommentCount: comments?.reviewComments.count ?? 0
        )
    }

    public func execute(prNumber: String) -> AsyncThrowingStream<PhaseProgress<SyncSnapshot>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .sync))

            Task {
                do {
                    try Task.checkCancellation()

                    let (gitHub, gitOps) = try await GitHubServiceFactory.create(repoPath: config.repoPath, tokenOverride: config.githubToken)
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

                    let snapshot = Self.parseOutput(config: config, prNumber: prNumber)
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
