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
    public let suppressedCount: Int
    public let violations: [PRComment]
    public let posted: Bool

    public init(successful: Int, failed: Int, skipped: Int = 0, edited: Int = 0, editFailed: Int = 0, suppressedCount: Int = 0, violations: [PRComment], posted: Bool) {
        self.successful = successful
        self.failed = failed
        self.skipped = skipped
        self.edited = edited
        self.editFailed = editFailed
        self.suppressedCount = suppressedCount
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
        let reconciled = fetchUseCase.execute(prNumber: prNumber, minScore: scoreThreshold, commitHash: commitHash)
        let allComments = CommentSuppressionService.applySuppression(to: reconciled).comments

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

    struct CommentToPost: Sendable {
        let comment: PRComment
        let suppressedCount: Int
    }

    private struct CategorizedComments {
        let newViolations: [CommentToPost]
        let updatePairs: [(post: CommentToPost, commentId: Int)]
        let skippedCount: Int
        let suppressedComments: [PRComment]

        var allViolations: [PRComment] {
            newViolations.map(\.comment) + updatePairs.map(\.post.comment)
        }
    }

    private func categorize(_ allComments: [ReviewComment]) -> CategorizedComments {
        let newViolations: [CommentToPost] = allComments
            .filter { $0.state == .new && !$0.isSuppressed }
            .compactMap { rc in
                guard let pending = rc.pending else { return nil }
                let suppressed = suppressedCountForLimiting(comment: rc, allComments: allComments)
                return CommentToPost(comment: pending, suppressedCount: suppressed)
            }
        let updatePairs: [(post: CommentToPost, commentId: Int)] = allComments
            .filter { $0.state == .needsUpdate && !$0.isSuppressed }
            .compactMap { rc in
                guard let pending = rc.pending,
                      let posted = rc.posted,
                      let commentId = Int(posted.id) else { return nil }
                let suppressed = suppressedCountForLimiting(comment: rc, allComments: allComments)
                return (post: CommentToPost(comment: pending, suppressedCount: suppressed), commentId: commentId)
            }
        let skippedCount = allComments.filter { $0.state == .redetected }.count
        let suppressedComments = allComments
            .filter { $0.isSuppressed }
            .compactMap { $0.pending }

        return CategorizedComments(
            newViolations: newViolations,
            updatePairs: updatePairs,
            skippedCount: skippedCount,
            suppressedComments: suppressedComments
        )
    }

    private func suppressedCountForLimiting(comment: ReviewComment, allComments: [ReviewComment]) -> Int {
        guard comment.suppressionRole == .limiting, let ruleName = comment.ruleName else { return 0 }
        return CommentSuppressionService.suppressedCount(
            in: allComments, ruleName: ruleName, filePath: comment.filePath
        )
    }

    private func logDryRun(
        categorized: CategorizedComments,
        continuation: AsyncThrowingStream<PhaseProgress<CommentPhaseOutput>, Error>.Continuation
    ) -> CommentPhaseOutput {
        if !categorized.newViolations.isEmpty {
            continuation.yield(.log(text: "Dry run: \(categorized.newViolations.count) new comments would be posted\n"))
            for v in categorized.newViolations {
                let limitingSuffix = v.suppressedCount > 0 ? " (limiting: \(v.suppressedCount) more suppressed)" : ""
                continuation.yield(.log(text: "  [\(v.comment.score)/10] \(v.comment.ruleName) - \(v.comment.filePath):\(v.comment.lineNumber ?? 0)\(limitingSuffix)\n"))
            }
        }
        if !categorized.updatePairs.isEmpty {
            continuation.yield(.log(text: "Dry run: \(categorized.updatePairs.count) comments would be edited\n"))
            for (v, _) in categorized.updatePairs {
                let limitingSuffix = v.suppressedCount > 0 ? " (limiting: \(v.suppressedCount) more suppressed)" : ""
                continuation.yield(.log(text: "  [edit] [\(v.comment.score)/10] \(v.comment.ruleName) - \(v.comment.filePath):\(v.comment.lineNumber ?? 0)\(limitingSuffix)\n"))
            }
        }
        if !categorized.suppressedComments.isEmpty {
            continuation.yield(.log(text: "\(categorized.suppressedComments.count) comments suppressed\n"))
            for v in categorized.suppressedComments {
                continuation.yield(.log(text: "  [SUPPRESSED] [\(v.score)/10] \(v.ruleName) - \(v.filePath):\(v.lineNumber ?? 0)\n"))
            }
        }
        return CommentPhaseOutput(
            successful: 0, failed: 0, skipped: categorized.skippedCount,
            suppressedCount: categorized.suppressedComments.count,
            violations: categorized.allViolations, posted: false
        )
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
                comments: categorized.newViolations.map { ($0.comment, $0.suppressedCount) },
                prNumber: prNumber
            )
            successful = s
            postFailed = f
        }

        if !categorized.updatePairs.isEmpty {
            continuation.yield(.log(text: "Editing \(categorized.updatePairs.count) existing comments...\n"))
            let (s, f) = try await commentService.editViolations(
                comments: categorized.updatePairs.map { ($0.post.comment, $0.post.suppressedCount, $0.commentId) },
                prNumber: prNumber
            )
            edited = s
            editFailed = f
        }

        if !categorized.suppressedComments.isEmpty {
            continuation.yield(.log(text: "\(categorized.suppressedComments.count) comments suppressed (not posted)\n"))
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
            suppressedCount: categorized.suppressedComments.count,
            violations: categorized.allViolations,
            posted: true
        )
    }
}
