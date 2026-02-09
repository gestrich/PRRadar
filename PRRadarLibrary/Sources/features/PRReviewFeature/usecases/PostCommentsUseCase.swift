import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct CommentPhaseOutput: Sendable {
    public let successful: Int
    public let failed: Int
    public let violations: [PRComment]
    public let posted: Bool

    public init(successful: Int, failed: Int, violations: [PRComment], posted: Bool) {
        self.successful = successful
        self.failed = failed
        self.violations = violations
        self.posted = posted
    }
}

public struct PostCommentsUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(
        prNumber: String,
        minScore: String? = nil,
        dryRun: Bool = true
    ) -> AsyncThrowingStream<PhaseProgress<CommentPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .evaluations))

            Task {
                do {
                    guard let prNum = Int(prNumber) else {
                        continuation.yield(.failed(error: "Invalid PR number: \(prNumber)", logs: ""))
                        continuation.finish()
                        return
                    }

                    let prOutputDir = "\(config.absoluteOutputDir)/\(prNumber)"
                    let scoreThreshold = Int(minScore ?? "5") ?? 5

                    let evalsDir = "\(prOutputDir)/\(PRRadarPhase.evaluations.rawValue)"
                    let tasksDir = "\(prOutputDir)/\(PRRadarPhase.tasks.rawValue)"
                    let violations = ViolationService.loadViolations(
                        evaluationsDir: evalsDir,
                        tasksDir: tasksDir,
                        minScore: scoreThreshold
                    )

                    if violations.isEmpty {
                        continuation.yield(.log(text: "No violations found above score threshold \(scoreThreshold)\n"))
                        let output = CommentPhaseOutput(successful: 0, failed: 0, violations: [], posted: false)
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    }

                    if dryRun {
                        continuation.yield(.log(text: "Dry run: \(violations.count) comments would be posted\n"))
                        for v in violations {
                            continuation.yield(.log(text: "  [\(v.score)/10] \(v.ruleName) - \(v.filePath):\(v.lineNumber ?? 0)\n"))
                        }
                        let output = CommentPhaseOutput(successful: 0, failed: 0, violations: violations, posted: false)
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.log(text: "Posting \(violations.count) comments...\n"))

                    let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, tokenOverride: config.githubToken)
                    let commentService = CommentService(githubService: gitHub)

                    let (successful, failed) = try await commentService.postViolations(
                        comments: violations,
                        prNumber: prNum
                    )

                    continuation.yield(.log(text: "Posted: \(successful) successful, \(failed) failed\n"))

                    let output = CommentPhaseOutput(
                        successful: successful,
                        failed: failed,
                        violations: violations,
                        posted: true
                    )
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }
}
