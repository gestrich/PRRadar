import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct DiffPhaseSnapshot: Sendable {
    public let files: [String]
    public let fullDiff: GitDiff?
    public let effectiveDiff: GitDiff?
    public let moveReport: MoveReport?

    public init(files: [String], fullDiff: GitDiff?, effectiveDiff: GitDiff?, moveReport: MoveReport?) {
        self.files = files
        self.fullDiff = fullDiff
        self.effectiveDiff = effectiveDiff
        self.moveReport = moveReport
    }
}

public struct FetchDiffUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public static func parseOutput(config: PRRadarConfig, prNumber: String) -> DiffPhaseSnapshot {
        let files = OutputFileReader.files(
            in: config,
            prNumber: prNumber,
            phase: .pullRequest
        )

        let fullDiff: GitDiff? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .pullRequest, filename: "diff-parsed.json"
        )

        let effectiveDiff: GitDiff? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .pullRequest, filename: "effective-diff-parsed.json"
        )

        let moveReport: MoveReport? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .pullRequest, filename: "effective-diff-moves.json"
        )

        return DiffPhaseSnapshot(files: files, fullDiff: fullDiff, effectiveDiff: effectiveDiff, moveReport: moveReport)
    }

    public func execute(prNumber: String) -> AsyncThrowingStream<PhaseProgress<DiffPhaseSnapshot>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .pullRequest))

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

                    continuation.yield(.log(text: "Diff acquired: \(result.diff.hunks.count) hunks across \(result.diff.uniqueFiles.count) files\n"))

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
