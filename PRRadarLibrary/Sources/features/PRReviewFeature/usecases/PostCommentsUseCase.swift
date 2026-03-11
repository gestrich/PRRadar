import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

private let defaultMinScore = 5

public struct CommentPhaseOutput: Sendable {
    public let successful: Int
    public let failed: Int
    public let skipped: Int
    public let edited: Int
    public let editFailed: Int
    public let violations: [PRComment]
    public let posted: Bool

    public init(successful: Int, failed: Int, skipped: Int = 0, edited: Int = 0, editFailed: Int = 0, violations: [PRComment], posted: Bool) {
        self.successful = successful
        self.failed = failed
        self.skipped = skipped
        self.edited = edited
        self.editFailed = editFailed
        self.violations = violations
        self.posted = posted
    }
}

public struct PostCommentsUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(
        prNumber: Int,
        minScore: String? = nil,
        dryRun: Bool = true,
        commitHash: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<CommentPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .analyze))

            Task {
                do {
                    let output = try await run(prNumber: prNumber, minScore: minScore, dryRun: dryRun, commitHash: commitHash, continuation: continuation)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    private func run(
        prNumber: Int,
        minScore: String?,
        dryRun: Bool,
        commitHash: String?,
        continuation: AsyncThrowingStream<PhaseProgress<CommentPhaseOutput>, Error>.Continuation
    ) async throws -> CommentPhaseOutput {
        let scoreThreshold = Int(minScore ?? "") ?? defaultMinScore

        let fetchUseCase = FetchReviewCommentsUseCase(config: config)
        let allComments = fetchUseCase.execute(prNumber: prNumber, minScore: scoreThreshold, commitHash: commitHash)

        let categorized = categorize(allComments)

        if categorized.newViolations.isEmpty && categorized.updatePairs.isEmpty && categorized.skippedCount == 0 {
            continuation.yield(.log(text: "No violations found above score threshold \(scoreThreshold)\n"))
            return CommentPhaseOutput(successful: 0, failed: 0, violations: [], posted: false)
        }

        if categorized.skippedCount > 0 {
            continuation.yield(.log(text: "Skipping \(categorized.skippedCount) already-posted comments\n"))
        }

        if categorized.newViolations.isEmpty && categorized.updatePairs.isEmpty {
            continuation.yield(.log(text: "All violations already posted — nothing new to comment\n"))
            return CommentPhaseOutput(successful: 0, failed: 0, skipped: categorized.skippedCount, violations: [], posted: false)
        }

        if dryRun {
            return logDryRun(categorized: categorized, continuation: continuation)
        }

        return try await postAndEdit(categorized: categorized, prNumber: prNumber, continuation: continuation)
    }

    private struct CategorizedComments {
        let newViolations: [PRComment]
        let updatePairs: [(pending: PRComment, commentId: Int)]
        let skippedCount: Int

        var allViolations: [PRComment] {
            newViolations + updatePairs.map(\.pending)
        }
    }

    private func categorize(_ allComments: [ReviewComment]) -> CategorizedComments {
        let newViolations = allComments.filter { $0.state == .new }.compactMap { $0.pending }
        let updatePairs: [(pending: PRComment, commentId: Int)] = allComments
            .filter { $0.state == .needsUpdate }
            .compactMap { rc in
                guard let pending = rc.pending,
                      let posted = rc.posted,
                      let commentId = Int(posted.id) else { return nil }
                return (pending: pending, commentId: commentId)
            }
        let skippedCount = allComments.filter { $0.state == .redetected }.count
        return CategorizedComments(newViolations: newViolations, updatePairs: updatePairs, skippedCount: skippedCount)
    }

    private func logDryRun(
        categorized: CategorizedComments,
        continuation: AsyncThrowingStream<PhaseProgress<CommentPhaseOutput>, Error>.Continuation
    ) -> CommentPhaseOutput {
        if !categorized.newViolations.isEmpty {
            continuation.yield(.log(text: "Dry run: \(categorized.newViolations.count) new comments would be posted\n"))
            for v in categorized.newViolations {
                continuation.yield(.log(text: "  [\(v.score)/10] \(v.ruleName) - \(v.filePath):\(v.lineNumber ?? 0)\n"))
            }
        }
        if !categorized.updatePairs.isEmpty {
            continuation.yield(.log(text: "Dry run: \(categorized.updatePairs.count) comments would be edited\n"))
            for (v, _) in categorized.updatePairs {
                continuation.yield(.log(text: "  [edit] [\(v.score)/10] \(v.ruleName) - \(v.filePath):\(v.lineNumber ?? 0)\n"))
            }
        }
        return CommentPhaseOutput(successful: 0, failed: 0, skipped: categorized.skippedCount, violations: categorized.allViolations, posted: false)
    }

    private func postAndEdit(
        categorized: CategorizedComments,
        prNumber: Int,
        continuation: AsyncThrowingStream<PhaseProgress<CommentPhaseOutput>, Error>.Continuation
    ) async throws -> CommentPhaseOutput {
        let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)
        let commentService = CommentService(githubService: gitHub)

        var successful = 0
        var postFailed = 0
        var edited = 0
        var editFailed = 0

        if !categorized.newViolations.isEmpty {
            continuation.yield(.log(text: "Posting \(categorized.newViolations.count) new comments...\n"))
            let (s, f) = try await commentService.postViolations(
                comments: categorized.newViolations,
                prNumber: prNumber
            )
            successful = s
            postFailed = f
        }

        if !categorized.updatePairs.isEmpty {
            continuation.yield(.log(text: "Editing \(categorized.updatePairs.count) existing comments...\n"))
            let (s, f) = try await commentService.editViolations(
                comments: categorized.updatePairs,
                prNumber: prNumber
            )
            edited = s
            editFailed = f
        }

        var logParts: [String] = []
        if successful > 0 || postFailed > 0 {
            logParts.append("Posted: \(successful) successful, \(postFailed) failed")
        }
        if edited > 0 || editFailed > 0 {
            logParts.append("Edited: \(edited) successful, \(editFailed) failed")
        }
        continuation.yield(.log(text: logParts.joined(separator: ". ") + "\n"))

        return CommentPhaseOutput(
            successful: successful,
            failed: postFailed,
            skipped: categorized.skippedCount,
            edited: edited,
            editFailed: editFailed,
            violations: categorized.allViolations,
            posted: true
        )
    }
}
